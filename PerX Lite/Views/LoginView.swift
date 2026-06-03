import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 40)
                        header
                            .padding(.bottom, 12)

                        VStack(spacing: 12) {
                            TextField("Email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await submit() } }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isLoading)

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        Button {
                            focusedField = nil
                            Task { await submit() }
                        } label: {
                            Text(isLoading ? "Accesso in corso…" : "Accedi")
                        }
                        .buttonStyle(PrimaryButtonStyle(
                            isLoading: isLoading,
                            background: canSubmit ? .accentColor : .gray
                        ))
                        .disabled(!canSubmit || isLoading)

                        if isLoading && !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("Server")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(APIClient.shared.baseURL)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .disabled(isLoading)

            if isLoading {
                WorkingOverlay(message: statusMessage.isEmpty ? "Accesso in corso…" : statusMessage)
                    .allowsHitTesting(true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
            Text("PerX Lite")
                .font(.largeTitle.bold())
            Text("Accedi al tuo account PerX")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    @MainActor
    private func submit() async {
        guard canSubmit, !isLoading else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        isLoading = true
        statusMessage = "Connessione al server…"
        defer {
            isLoading = false
            statusMessage = ""
        }
        do {
            statusMessage = "Verifica credenziali…"
            try await auth.login(email: email, password: password)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
