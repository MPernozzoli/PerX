//
//  SessionCoordinator.swift
//  PerX per iPad
//
//  Gestisce l'isolamento totale per utente: store CoreData, cache, servizi CloudKit.
//  Al cambio utente, tutti i dati locali vengono resettati immediatamente.
//

import Foundation
import CoreData
import Combine
import CloudKit

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
    
    // MARK: - Servizi (resettabili)
    
    private(set) var cloudKitSyncService: iPadCloudKitSyncService?
    private(set) var chatService: iPadChatService?
    private(set) var folderCacheService: SinistroFolderCacheService?
    
    // Hub services (singleton, ma resettabili)
    var hubClient: HubAPIClient { HubAPIClient.shared }
    var outboxService: HubOutboxService { HubOutboxService.shared }
    
    // MARK: - Auth Service
    
    private let authService = GoogleAuthServiceiOS.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    private init() {
        // Osserva cambi di autenticazione
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
        
        // Check iniziale
        Task {
            await authService.checkAuthenticationState()
        }
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
    
    // MARK: - Session Lifecycle
    
    private func setupSession(for email: String, name: String?) async {
        let normalizedEmail = email.lowercased()
        
        // Se è lo stesso utente, skip
        if currentUserEmail == normalizedEmail && isAuthenticated {
            return
        }
        
        // Teardown sessione precedente (se diverso utente)
        if currentUserEmail != nil && currentUserEmail != normalizedEmail {
            await tearDownSession()
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("[SessionCoordinator] 🔐 Setup sessione per: \(normalizedEmail)")
        
        // 1. CoreData per-utente
        persistenceController = UserScopedPersistenceController(userEmail: normalizedEmail)
        
        // 2. Servizi CloudKit
        cloudKitSyncService = iPadCloudKitSyncService(userEmail: normalizedEmail)
        chatService = iPadChatService(userEmail: normalizedEmail)
        folderCacheService = SinistroFolderCacheService(userEmail: normalizedEmail)
        
        // 3. Avvia sync
        await cloudKitSyncService?.start()
        await chatService?.start()
        
        // 4. Purge cartelle scadute (>3gg)
        await folderCacheService?.purgeExpiredFolders()
        
        // 5. Aggiorna stato
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
        
        // 1. Stop servizi CloudKit
        cloudKitSyncService?.stop()
        chatService?.stop()
        
        // 2. Cleanup cache effimere (cartelle >3gg applicate al logout)
        await folderCacheService?.purgeExpiredFolders()
        
        // 3. Rilascia riferimenti
        cloudKitSyncService = nil
        chatService = nil
        folderCacheService = nil
        persistenceController = nil
        
        // 4. Reset stato
        currentUserEmail = nil
        currentUserName = nil
        currentCloudProfile = nil
        isAuthenticated = false
        
        print("[SessionCoordinator] ✅ Sessione terminata")
    }
    
    // MARK: - User-scoped Helpers
    
    /// Restituisce UserDefaults key namespaced per utente corrente
    func userDefaultsKey(_ baseKey: String) -> String {
        guard let email = currentUserEmail else { return baseKey }
        return "\(baseKey)_\(email)"
    }
    
    /// Restituisce directory cache per utente corrente
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
