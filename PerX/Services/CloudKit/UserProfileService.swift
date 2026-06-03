import Foundation
import Combine
import AppKit

/// Servizio per gestire i profili utente tramite backend Supabase con cache locale.
@MainActor
final class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    
    @Published private(set) var currentProfile: UserProfile?
    @Published private(set) var allProfiles: [UserProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    /// True se l'utente corrente ha ruolo admin.
    var isCurrentUserAdmin: Bool {
        guard let p = currentProfile else { return false }
        return p.isAdmin
    }

    var canCurrentUserManageTenantSettings: Bool {
        currentProfile?.canManageTenantSettings ?? false
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private let storageKey = "userProfileLocal"
    private let allProfilesKey = "allUserProfiles"
    
    private init() {
        // Carica profilo locale
        loadLocalProfile()
        loadAllProfilesLocal()
        
        // Osserva cambio account Google
        NotificationCenter.default.publisher(for: .init("GoogleAuthStateChanged"))
            .sink { [weak self] notification in
                guard let self else { return }
                let signedOut = (notification.userInfo?["signedOut"] as? Bool) ?? false
                if signedOut {
                    Task { await self.clearCurrentProfile() }
                } else {
                    Task { await self.refreshCurrentProfile() }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// Inizializza o aggiorna il profilo corrente
    func refreshCurrentProfile() async {
        let backendConfigured = BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? CurrentUserService.shared.currentEmail?.lowercased()
        guard let email = currentEmail, !email.isEmpty else {
            currentProfile = nil
            return
        }
        
        // Se c'è un profilo locale di un utente diverso, svuotalo
        if let existing = currentProfile, existing.email.lowercased() != email {
            print("[UserProfileService] ⚠️ Cambio utente rilevato, svuoto profilo precedente")
            currentProfile = nil
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        
        isLoading = true
        error = nil
        
        guard backendConfigured else {
            let cached = loadLocalProfile()
            var localProfile = cached?.email.lowercased() == email ? cached! : UserProfile(email: email)
            localProfile.username = UserProfile.validatedUsername(localProfile.username, email: email).0
            currentProfile = localProfile
            saveLocalProfile(localProfile)
            isLoading = false
            Task { await refreshAllProfiles() }
            return
        }

        do {
            let dto: BackendUserProfileDTO = try await BackendAPIClient.shared.get("profiles/me")
            let profile = try await resolveProfileAssets(for: dto.toUserProfile())
            currentProfile = profile
            saveLocalProfile(profile)
        } catch {
            self.error = error.localizedDescription
            print("[UserProfileService] ❌ backend refreshCurrentProfile: \(error)")
        }
        
        isLoading = false
        
        // Refresh tutti i profili in background
        Task { await refreshAllProfiles() }
    }
    
    /// Salva le modifiche al profilo corrente
    func saveCurrentProfile() async throws {
        guard var profile = currentProfile else { return }
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalProfile(profile)
        if BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken {
            let dto: BackendUserProfileDTO = try await BackendAPIClient.shared.put(
                "profiles/me",
                body: BackendUserProfileUpdateDTO(profile: profile)
            )
            let saved = try await resolveProfileAssets(for: dto.toUserProfile())
            currentProfile = saved
            saveLocalProfile(saved)
            await refreshAllProfiles()
            return
        }
        saveLocalProfile(profile)
    }
    
    /// Aggiorna un campo specifico del profilo
    func updateProfile(_ update: (inout UserProfile) -> Void) async throws {
        guard var profile = currentProfile else { return }
        update(&profile)
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalProfile(profile)
        try await saveCurrentProfile()
    }
    
    /// Ottiene tutti gli utenti che hanno il compleanno oggi
    func birthdaysToday() -> [UserProfile] {
        allProfiles.filter { profile in
            profile.notifyBirthday && profile.birthdayToday
        }
    }
    
    /// Ottiene il profilo di un utente per email
    func profile(for email: String) -> UserProfile? {
        allProfiles.first { $0.email.lowercased() == email.lowercased() }
    }
    
    /// Refresh tutti i profili dal backend Supabase.
    func refreshAllProfiles() async {
        guard BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken else {
            allProfiles = currentProfile.map { [$0] } ?? loadAllProfilesLocal()
            return
        }

        do {
            let profiles: [BackendUserProfileDTO] = try await BackendAPIClient.shared.get("profiles")
            let mapped = profiles.map { $0.toUserProfile() }
            allProfiles = mapped
            saveAllProfilesLocal(mapped)
        } catch {
            print("[UserProfileService] ⚠️ backend refreshAllProfiles: \(error)")
        }
    }
    
    /// Pulisce il profilo corrente (logout)
    func clearCurrentProfile() async {
        currentProfile = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("[UserProfileService] 🚪 Profilo utente cancellato (logout)")
    }
    
    // MARK: - Avatar Management
    
    /// Imposta una foto come avatar
    func setAvatarPhoto(_ image: NSImage) async throws {
        guard var profile = currentProfile else { return }
        
        // Ridimensiona e comprimi
        guard let resized = resizeImage(image, maxSize: 256),
              let data = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let compressed = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw NSError(domain: "UserProfileService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossibile processare l'immagine"])
        }
        
        profile.avatarType = .photo
        profile.avatarPhotoData = compressed
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalProfile(profile)
        if BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken {
            let response: BackendUserProfileAssetDTO = try await BackendAPIClient.shared.upload(
                "profiles/me/assets/avatar_photo",
                data: compressed,
                fileName: "avatar.jpg",
                mimeType: "image/jpeg"
            )
            profile.avatarAssetURL = response.asset_url
            profile.avatarType = .photo
            profile.avatarPhotoData = compressed
            currentProfile = profile
            saveLocalProfile(profile)
            try await saveCurrentProfile()
            return
        }
        try await saveCurrentProfile()
    }
    
    /// Imposta un avatar generato
    func setGeneratedAvatar(backgroundColor: String, icon: String) async throws {
        try await updateProfile { profile in
            profile.avatarType = .generated
            profile.generatedAvatar = GeneratedAvatar(backgroundColor: backgroundColor, icon: icon)
        }
    }
    
    /// Imposta una GIF come avatar
    func setAvatarGif(url: String) async throws {
        try await updateProfile { profile in
            profile.avatarType = .gif
            profile.avatarGifURL = url
        }
    }

    func removeAvatarPhoto() async throws {
        guard var profile = currentProfile else { return }
        profile.avatarType = .generated
        profile.avatarPhotoData = nil
        profile.avatarAssetURL = nil
        currentProfile = profile
        saveLocalProfile(profile)
        if BackendAPIClient.shared.isConfigured && BackendAPIClient.shared.hasAccessToken {
            try await BackendAPIClient.shared.delete("profiles/me/assets/avatar_photo")
            try await saveCurrentProfile()
            return
        }
        try await saveCurrentProfile()
    }
    
    // MARK: - Local Storage
    
    private func saveLocalProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    @discardableResult
    private func loadLocalProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return nil }
        
        // Non caricare profilo se appartiene a un utente diverso da quello autenticato
        if let currentEmail = GoogleAuthService.shared.userEmail?.lowercased(),
           !currentEmail.isEmpty,
           profile.email.lowercased() != currentEmail {
            print("[UserProfileService] ⚠️ Profilo locale appartiene a utente diverso, ignorato")
            UserDefaults.standard.removeObject(forKey: storageKey)
            return nil
        }
        
        let (validated, _) = UserProfile.validatedUsername(profile.username, email: profile.email)
        profile.username = validated
        currentProfile = profile
        return profile
    }
    
    private func saveAllProfilesLocal(_ profiles: [UserProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: allProfilesKey)
        }
    }
    
    @discardableResult
    private func loadAllProfilesLocal() -> [UserProfile] {
        guard let data = UserDefaults.standard.data(forKey: allProfilesKey),
              var profiles = try? JSONDecoder().decode([UserProfile].self, from: data) else { return [] }
        for i in profiles.indices {
            profiles[i].username = UserProfile.validatedUsername(profiles[i].username, email: profiles[i].email).0
        }
        allProfiles = profiles
        return profiles
    }
    
    // MARK: - Helpers
    
    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage? {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }

    private func resolveProfileAssets(for profile: UserProfile) async throws -> UserProfile {
        var resolved = profile
        if let assetURL = profile.avatarAssetURL,
           profile.avatarPhotoData == nil,
           let path = normalizedBackendPath(from: assetURL) {
            resolved.avatarPhotoData = try? await BackendAPIClient.shared.download(path)
        }
        return resolved
    }

    private func normalizedBackendPath(from urlOrPath: String) -> String? {
        if urlOrPath.hasPrefix("/api/v1/") {
            return String(urlOrPath.dropFirst("/api/v1/".count))
        }
        if urlOrPath.hasPrefix("/api/") {
            return String(urlOrPath.dropFirst("/api/".count))
        }
        if urlOrPath.hasPrefix("/") {
            return String(urlOrPath.dropFirst())
        }
        if let url = URL(string: urlOrPath), let path = url.path.isEmpty ? nil : url.path {
            if path.hasPrefix("/api/v1/") {
                return String(path.dropFirst("/api/v1/".count))
            }
            return path.hasPrefix("/") ? String(path.dropFirst()) : path
        }
        return urlOrPath.isEmpty ? nil : urlOrPath
    }
}

private struct BackendUserProfileDTO: Codable {
    let id: String
    let email: String
    let personal_email: String?
    let professional_email: String?
    let email_aliases: [String]?
    let full_name: String
    let first_name: String
    let last_name: String
    let job_title: String?
    let phone_number: String?
    let birth_date: Date?
    let birthday_visibility: String
    let notify_birthday: Bool
    let contract_type: String?
    let roles: [String]
    let extension_number: String?
    let extension_enabled: Bool?
    let extension_assigned_at: Date?
    let extension_display_name: String?
    let availability_status: String?
    let communication_status: String?
    let avatar_type: String
    let avatar_photo_base64: String?
    let avatar_asset_url: String?
    let generated_avatar_color: String?
    let generated_avatar_icon: String?
    let avatar_gif_url: String?
    let signature_image_url: String?
    let enable_badges: Bool
    let send_read_receipts: Bool
    let email_signature_html: String?
    let email_signature_text: String?
    let created_at: Date?
    let updated_at: Date?

    func toUserProfile() -> UserProfile {
        var profile = UserProfile(email: email)
        profile.personalEmail = personal_email ?? email
        profile.professionalEmail = professional_email
        profile.emailAliases = email_aliases ?? []
        profile.firstName = first_name
        profile.lastName = last_name
        profile.jobTitle = job_title
        profile.phoneNumber = phone_number
        profile.birthDate = birth_date
        profile.birthdayVisibility = BirthdayVisibility(rawValue: birthday_visibility) ?? .everyone
        profile.notifyBirthday = notify_birthday
        profile.contractType = contract_type.flatMap(ContractType.init(rawValue:))
        profile.roles = roles.compactMap(UserRole.init(rawValue:))
        profile.extensionNumber = extension_number
        profile.extensionEnabled = extension_enabled ?? false
        profile.extensionAssignedAt = extension_assigned_at
        profile.extensionDisplayName = extension_display_name
        profile.availabilityStatus = availability_status.flatMap(AvailabilityStatus.init(rawValue:)) ?? .available
        profile.communicationStatus = communication_status.flatMap(CommunicationStatus.init(rawValue:)) ?? .idle
        profile.avatarType = AvatarType(rawValue: avatar_type) ?? .generated
        if let avatar_photo_base64,
           let data = Data(base64Encoded: avatar_photo_base64) {
            profile.avatarPhotoData = data
        }
        profile.avatarAssetURL = avatar_asset_url
        profile.generatedAvatar = GeneratedAvatar(
            backgroundColor: generated_avatar_color ?? GeneratedAvatar.default.backgroundColor,
            icon: generated_avatar_icon ?? GeneratedAvatar.default.icon
        )
        profile.avatarGifURL = avatar_gif_url
        profile.signatureImageURL = signature_image_url
        profile.enableBadges = enable_badges
        profile.sendReadReceipts = send_read_receipts
        profile.emailSignatureHTML = email_signature_html
        profile.emailSignatureText = email_signature_text
        profile.createdAt = created_at ?? Date()
        profile.updatedAt = updated_at ?? Date()
        return profile
    }
}

private struct BackendUserProfileUpdateDTO: Encodable {
    let first_name: String
    let last_name: String
    let job_title: String?
    let phone_number: String?
    let birth_date: Date?
    let birthday_visibility: String
    let notify_birthday: Bool
    let contract_type: String?
    let roles: [String]
    let extension_number: String?
    let extension_enabled: Bool?
    let extension_assigned_at: Date?
    let extension_display_name: String?
    let availability_status: String?
    let communication_status: String?
    let avatar_type: String
    let avatar_photo_base64: String?
    let generated_avatar_color: String?
    let generated_avatar_icon: String?
    let avatar_gif_url: String?
    let enable_badges: Bool
    let send_read_receipts: Bool
    let email_signature_html: String?
    let email_signature_text: String?
    let professional_email: String?

    init(profile: UserProfile) {
        self.first_name = profile.firstName
        self.last_name = profile.lastName
        self.job_title = profile.jobTitle
        self.phone_number = profile.phoneNumber
        self.birth_date = profile.birthDate
        self.birthday_visibility = profile.birthdayVisibility.rawValue
        self.notify_birthday = profile.notifyBirthday
        self.contract_type = profile.contractType?.rawValue
        self.roles = profile.roles.map(\.rawValue)
        self.extension_number = profile.extensionNumber
        self.extension_enabled = profile.extensionEnabled
        self.extension_assigned_at = profile.extensionAssignedAt
        self.extension_display_name = profile.extensionDisplayName
        self.availability_status = profile.availabilityStatus?.rawValue
        self.communication_status = profile.communicationStatus?.rawValue
        self.avatar_type = profile.avatarType.rawValue
        self.avatar_photo_base64 = profile.avatarAssetURL == nil ? profile.avatarPhotoData?.base64EncodedString() : nil
        self.generated_avatar_color = profile.generatedAvatar.backgroundColor
        self.generated_avatar_icon = profile.generatedAvatar.icon
        self.avatar_gif_url = profile.avatarGifURL
        self.enable_badges = profile.enableBadges
        self.send_read_receipts = profile.sendReadReceipts
        self.email_signature_html = profile.emailSignatureHTML
        self.email_signature_text = profile.emailSignatureText
        self.professional_email = profile.professionalEmail
    }
}

private struct BackendUserProfileAssetDTO: Decodable {
    let asset_type: String
    let file_name: String
    let mime_type: String?
    let size_bytes: Int
    let asset_url: String
}
