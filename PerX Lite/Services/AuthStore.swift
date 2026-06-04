import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var email: String?
    @Published var displayName: String?
    @Published var myExtension: String?
    @Published var myExtensionEnabled: Bool = false
    @Published var tenantId: String?
    @Published var roles: [String] = []

    var isCATUser: Bool {
        roles.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.contains("cat")
    }

    init() {
        self.isAuthenticated = APIClient.shared.isLoggedIn
        self.email = APIClient.shared.userEmail
        if isAuthenticated {
            Task { await refreshProfile() }
        }
    }

    func login(email: String, password: String) async throws {
        try await APIClient.shared.login(email: email, password: password)
        self.email = APIClient.shared.userEmail
        self.isAuthenticated = true
        await refreshProfile()
    }

    func logout() async {
        await CallSessionShared.shared.endActive()
        await PushDispatcher.shared.unregisterAll()
        APIClient.shared.clearSession()
        self.email = nil
        self.displayName = nil
        self.myExtension = nil
        self.myExtensionEnabled = false
        self.roles = []
        self.isAuthenticated = false
    }

    func refreshProfile() async {
        do {
            let me: MeProfileDTO = try await APIClient.shared.get("/api/v1/profiles/me")
            self.myExtension = me.extension_number
            self.myExtensionEnabled = me.extension_enabled ?? false
            self.tenantId = me.tenant_id
            self.roles = me.roles ?? []
            let full = [me.first_name, me.last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            self.displayName = full.isEmpty ? me.email : full
        } catch {
            // Silenzioso: l'UI fallback non mostra il badge se il profilo non è caricato.
        }
    }
}
