import Foundation
import CoreData
import Combine

/// Gestisce l'isolamento per utente: store CoreData, cache, servizi API.
/// CloudKit rimosso: tutto il sync passa per il backend Supabase.
@MainActor
final class SessionCoordinator: ObservableObject {
    static let shared = SessionCoordinator()

    // MARK: - Published State

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var currentUserName: String?
    @Published private(set) var currentCloudProfile: CloudProfileDTO?
    @Published private(set) var isLoading = false

    // MARK: - Core Data (per-utente)

    private var persistenceController: UserScopedPersistenceController?

    var viewContext: NSManagedObjectContext {
        guard let controller = persistenceController else {
            fatalError("PersistenceController non inizializzato. Utente non autenticato?")
        }
        return controller.container.viewContext
    }

    // MARK: - Servizi

    private(set) var syncService: iPadSyncService?
    private(set) var chatService: iPadChatService?
    private(set) var folderCacheService: SinistroFolderCacheService?

    var hubClient: HubAPIClient { HubAPIClient.shared }
    var outboxService: HubOutboxService { HubOutboxService.shared }

    // MARK: - Auth Service

    private let authService = GoogleAuthServiceiOS.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        authService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                guard let self else { return }
                if isAuth, let email = self.authService.userEmail {
                    Task { await self.setupSession(for: email, name: self.authService.userName) }
                } else if !isAuth {
                    Task { await self.tearDownSession() }
                }
            }
            .store(in: &cancellables)

        Task { await authService.checkAuthenticationState() }
    }

    // MARK: - Public API

    func signIn() async throws {
        isLoading = true
        defer { isLoading = false }
        try await authService.signIn()
    }

    func signIn(email: String, password: String, baseURL: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        try await authService.signIn(email: email, password: password, baseURL: baseURL)
    }

    func signOut() async {
        await tearDownSession()
        authService.signOut()
    }

    var isCATUser: Bool {
        guard let profile = currentCloudProfile else { return false }
        return profile.roles.contains("cat")
    }

    // MARK: - Session Lifecycle

    private func setupSession(for email: String, name: String?) async {
        let normalizedEmail = email.lowercased()
        if currentUserEmail == normalizedEmail && isAuthenticated { return }
        if currentUserEmail != nil && currentUserEmail != normalizedEmail { await tearDownSession() }

        isLoading = true
        defer { isLoading = false }

        print("[SessionCoordinator] 🔐 Setup sessione per: \(normalizedEmail)")

        persistenceController = UserScopedPersistenceController(userEmail: normalizedEmail)
        syncService = iPadSyncService(userEmail: normalizedEmail)
        chatService = iPadChatService(userEmail: normalizedEmail)
        folderCacheService = SinistroFolderCacheService(userEmail: normalizedEmail)

        await syncService?.start()
        await chatService?.start()
        await folderCacheService?.purgeExpiredFolders()

        currentUserEmail = normalizedEmail
        currentUserName = name
        isAuthenticated = true

        if hubClient.isCloudConfigured {
            do {
                let profile = try await hubClient.getCurrentProfileFromCloud()
                currentCloudProfile = profile
                if !profile.displayName.isEmpty {
                    currentUserName = profile.displayName
                    accountManagerUpdateNameIfNeeded(email: normalizedEmail, displayName: profile.displayName)
                }
            } catch {
                print("[SessionCoordinator] ⚠️ Profilo cloud non disponibile: \(error)")
            }
        }

        print("[SessionCoordinator] ✅ Sessione attiva per: \(normalizedEmail)")
    }

    private func tearDownSession() async {
        guard currentUserEmail != nil else { return }
        print("[SessionCoordinator] 🔓 Teardown sessione per: \(currentUserEmail ?? "?")")

        syncService?.stop()
        chatService?.stop()
        await folderCacheService?.purgeExpiredFolders()

        syncService = nil
        chatService = nil
        folderCacheService = nil
        persistenceController = nil

        currentUserEmail = nil
        currentUserName = nil
        currentCloudProfile = nil
        isAuthenticated = false

        print("[SessionCoordinator] ✅ Sessione terminata")
    }

    // MARK: - Helpers

    func userDefaultsKey(_ baseKey: String) -> String {
        guard let email = currentUserEmail else { return baseKey }
        return "\(baseKey)_\(email)"
    }

    func userCacheDirectory() -> URL? {
        guard let email = currentUserEmail else { return nil }
        let hash = email.hash
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let userDir = cachesDir.appendingPathComponent("User_\(abs(hash))", isDirectory: true)
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        return userDir
    }

    private func accountManagerUpdateNameIfNeeded(email: String, displayName: String) {
        AccountManager.shared.updateDisplayName(displayName, for: email)
    }
}
