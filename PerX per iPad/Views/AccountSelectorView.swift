//
//  AccountSelectorView.swift
//  PerX per iPad
//
//  Login page stile Netflix con selezione account.
//

import SwiftUI

struct AccountSelectorView: View {
    @EnvironmentObject var session: SessionCoordinator
    @StateObject private var accountManager = AccountManager.shared
    
    @State private var isLoggingIn = false
    @State private var showingNewAccount = false
    @State private var showingPasscodeEntry = false
    @State private var passcodeInput = ""
    @State private var selectedAccount: AccountManager.SavedAccount?
    @State private var errorMessage: String?
    @State private var isEditing = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                Spacer()
                
                // Content
                if accountManager.savedAccounts.isEmpty {
                    noAccountsView
                } else {
                    accountGridView
                }
                
                Spacer()
                
                // Footer
                footerView
            }
            .padding()
        }
        .sheet(isPresented: $showingNewAccount) {
            NewAccountLoginView { success in
                if success {
                    showingNewAccount = false
                }
            }
        }
        .sheet(isPresented: $showingPasscodeEntry) {
            PasscodeEntryView(
                account: selectedAccount,
                onSuccess: {
                    showingPasscodeEntry = false
                    if let account = selectedAccount {
                        loginWithAccount(account)
                    }
                },
                onCancel: {
                    showingPasscodeEntry = false
                    selectedAccount = nil
                }
            )
        }
        .alert("Errore", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("PerX")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            if !accountManager.savedAccounts.isEmpty {
                Button {
                    withAnimation {
                        isEditing.toggle()
                    }
                } label: {
                    Text(isEditing ? "Fine" : "Modifica")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
    
    // MARK: - No Accounts View
    
    private var noAccountsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Nessun account")
                .font(.title)
                .foregroundColor(.white)
            
            Text("Configura backend, email e password\nper iniziare a usare PerX")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button {
                showingNewAccount = true
            } label: {
                Label("Aggiungi account", systemImage: "person.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Account Grid
    
    private var accountGridView: some View {
        VStack(spacing: 32) {
            Text("Chi sta usando PerX?")
                .font(.title2)
                .foregroundColor(.white.opacity(0.9))
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible(), spacing: 24)
            ], spacing: 32) {
                ForEach(accountManager.savedAccounts) { account in
                    AccountTileView(
                        account: account,
                        isEditing: isEditing,
                        onSelect: {
                            handleAccountSelection(account)
                        },
                        onDelete: {
                            accountManager.removeAccount(account)
                        }
                    )
                }
                
                // Add account tile
                AddAccountTileView {
                    showingNewAccount = true
                }
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        VStack(spacing: 8) {
            if isLoggingIn {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                Text("Accesso in corso...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(height: 60)
        .padding(.bottom, 20)
    }
    
    // MARK: - Actions
    
    private func handleAccountSelection(_ account: AccountManager.SavedAccount) {
        selectedAccount = account
        
        if account.hasPasscode {
            showingPasscodeEntry = true
        } else {
            loginWithAccount(account)
        }
    }
    
    private func loginWithAccount(_ account: AccountManager.SavedAccount) {
        isLoggingIn = true
        
        Task {
            do {
                if let password = accountManager.getPassword(for: account.email) {
                    try await GoogleAuthServiceiOS.shared.signIn(email: account.email, password: password)
                } else {
                    throw GoogleAuthServiceiOS.AuthError.missingSavedCredentials
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoggingIn = false
        }
    }
}

// MARK: - Account Tile

struct AccountTileView: View {
    let account: AccountManager.SavedAccount
    let isEditing: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
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
            VStack(spacing: 12) {
                ZStack {
                    // Avatar
                    Circle()
                        .fill(avatarColor.gradient)
                        .frame(width: 100, height: 100)
                    
                    Text(account.avatarInitials)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // Lock indicator
                    if account.hasPasscode {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                        }
                        .frame(width: 100, height: 100)
                    }
                    
                    // Delete button (editing mode)
                    if isEditing {
                        VStack {
                            HStack {
                                Button(action: onDelete) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        .frame(width: 110, height: 110)
                    }
                }
                
                Text(account.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(account.email)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
    }
}

// MARK: - Add Account Tile

struct AddAccountTileView: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Circle()
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.5))
                    }
                
                Text("Aggiungi account")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Account Login View

struct NewAccountLoginView: View {
    let onComplete: (Bool) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var backendURL: String
    @State private var email: String
    @State private var password: String
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    init(
        onComplete: @escaping (Bool) -> Void,
        initialEmail: String = "",
        initialPassword: String = ""
    ) {
        self.onComplete = onComplete
        _backendURL = State(initialValue: Self.defaultBackendURL())
        _email = State(initialValue: initialEmail)
        _password = State(initialValue: initialPassword)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Aggiungi account")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text("Accedi con email e password del backend PerX")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    VStack(spacing: 14) {
                        TextField("URL backend", text: $backendURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: 420)
                    
                    Button {
                        performLogin()
                    } label: {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                            }
                            
                            Text("Accedi e salva account")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: 320)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(
                        isLoggingIn ||
                        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Text("L'URL backend resta condiviso su questo iPad. In simulatore, se vuoto, viene proposto `http://127.0.0.1:8000`.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func performLogin() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBackendURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedEmail.isEmpty, !normalizedPassword.isEmpty else {
            errorMessage = "Inserisci email e password."
            return
        }

        isLoggingIn = true
        errorMessage = nil
        
        Task {
            do {
                try await GoogleAuthServiceiOS.shared.signIn(
                    email: normalizedEmail,
                    password: normalizedPassword,
                    baseURL: normalizedBackendURL
                )
                onComplete(true)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                onComplete(false)
            }
            isLoggingIn = false
        }
    }

    private static func defaultBackendURL() -> String {
        let saved = HubAPIClient.shared.cloudAPIBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty {
            return saved
        }
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        return ""
        #endif
    }
}

// MARK: - Passcode Entry View

struct PasscodeEntryView: View {
    let account: AccountManager.SavedAccount?
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @State private var passcode = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    private let passcodeLength = 4
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Avatar
                    if let account = account {
                        Circle()
                            .fill(Color.blue.gradient)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(account.avatarInitials)
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        
                        Text(account.displayName)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    
                    Text("Inserisci il codice di accesso")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // Passcode dots
                    HStack(spacing: 20) {
                        ForEach(0..<passcodeLength, id: \.self) { index in
                            Circle()
                                .fill(index < passcode.count ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 16, height: 16)
                        }
                    }
                    
                    // Hidden text field
                    TextField("", text: $passcode)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: passcode) { newValue in
                            // Limita a 4 cifre
                            if newValue.count > passcodeLength {
                                passcode = String(newValue.prefix(passcodeLength))
                            }
                            
                            // Verifica automatica
                            if newValue.count == passcodeLength {
                                verifyPasscode()
                            }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func verifyPasscode() {
        guard let account = account else { return }
        
        if AccountManager.shared.verifyPasscode(passcode, for: account.email) {
            onSuccess()
        } else {
            errorMessage = "Codice errato"
            passcode = ""
            
            // Vibrazione errore
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}
