import Foundation
import Combine

/// Servizio centralizzato per l'identificatore utente.
/// Usa il username (parte prima di @ nell'email, es. massimo.pernozzoli) come identificatore
/// canonico in Hub, CloudKit, WA e tutte le funzioni che necessitano sapere chi è connesso.
@MainActor
final class CurrentUserService: ObservableObject {
    static let shared = CurrentUserService()
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Indica se l'utente è autenticato
    var isAuthenticated: Bool {
        GoogleAuthService.shared.isAuthenticated
    }
    
    /// Username dell'utente connesso (es. massimo.pernozzoli da massimo.pernozzoli@gmail.com).
    /// Usare questo valore per Hub, CloudKit, tasks, sinistri, etc.
    /// Ritorna nil se l'utente non è autenticato.
    var currentUsername: String? {
        guard isAuthenticated else { return nil }
        if let profile = UserProfileService.shared.currentProfile {
            return profile.username
        }
        guard let email = GoogleAuthService.shared.userEmail?.trimmingCharacters(in: .whitespaces).lowercased(),
              !email.isEmpty else {
            return nil
        }
        return UserProfile.generateUsername(from: email)
    }
    
    /// Email dell'utente (per integrazioni che richiedono email, es. Gmail).
    /// Ritorna nil se l'utente non è autenticato.
    var currentEmail: String? {
        guard isAuthenticated else { return nil }
        return GoogleAuthService.shared.userEmail?.lowercased()
    }

    var currentRoles: [UserRole] {
        UserProfileService.shared.currentProfile?.roles ?? []
    }

    var isPlatformAdmin: Bool {
        UserProfileService.shared.currentProfile?.isPlatformAdmin ?? false
    }

    var isTenantAdmin: Bool {
        if UserProfileService.shared.currentProfile?.isTenantAdmin == true {
            return true
        }
        return currentEmail == "admin@perx.it"
    }

    var canManageTenantSettings: Bool {
        isPlatformAdmin || isTenantAdmin
    }
    
    /// Username o fallback se non autenticato
    func currentUsernameOrDefault(_ fallback: String = "unknown") -> String {
        currentUsername ?? fallback
    }
    
    private init() {
        // Osserva cambio stato auth per notificare osservatori
        GoogleAuthService.shared.$isAuthenticated
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        GoogleAuthService.shared.$userEmail
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        UserProfileService.shared.$currentProfile
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
