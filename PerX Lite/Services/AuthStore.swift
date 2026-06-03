import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var email: String?

    init() {
        self.isAuthenticated = APIClient.shared.isLoggedIn
        self.email = APIClient.shared.userEmail
    }

    func login(email: String, password: String) async throws {
        try await APIClient.shared.login(email: email, password: password)
        self.email = APIClient.shared.userEmail
        self.isAuthenticated = true
    }

    func logout() async {
        await CallSessionShared.shared.endActive()
        await PushDispatcher.shared.unregisterAll()
        APIClient.shared.clearSession()
        self.email = nil
        self.isAuthenticated = false
    }
}
