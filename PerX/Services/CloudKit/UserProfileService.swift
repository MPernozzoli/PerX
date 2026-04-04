import Foundation
import CloudKit
import Combine
import AppKit

/// Servizio per gestire i profili utente sincronizzati con CloudKit
@MainActor
final class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    
    @Published private(set) var currentProfile: UserProfile?
    @Published private(set) var allProfiles: [UserProfile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    /// True se l'utente corrente ha ruolo admin (CloudKit) o è l'admin hardcoded
    var isCurrentUserAdmin: Bool {
        guard let p = currentProfile else { return false }
        return p.isAdmin
    }

    var canCurrentUserManageTenantSettings: Bool {
        currentProfile?.canManageTenantSettings ?? false
    }
    
    private let container: CKContainer
    private let publicDB: CKDatabase
    private var cancellables = Set<AnyCancellable>()
    
    private let storageKey = "userProfileLocal"
    private let allProfilesKey = "allUserProfiles"
    
    private enum RecordType {
        static let userProfile = "UserProfile"
    }
    
    private enum Keys {
        static let email = "email"
        static let username = "username"
        static let firstName = "firstName"
        static let lastName = "lastName"
        static let birthDate = "birthDate"
        static let birthdayVisibility = "birthdayVisibility"
        static let notifyBirthday = "notifyBirthday"
        static let avatarType = "avatarType"
        static let avatarPhoto = "avatarPhoto"
        static let generatedAvatarColor = "generatedAvatarColor"
        static let generatedAvatarIcon = "generatedAvatarIcon"
        static let avatarGifURL = "avatarGifURL"
        static let contractType = "contractType"
        static let roles = "roles"
        static let enableBadges = "enableBadges"
        static let sendReadReceipts = "sendReadReceipts"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }
    
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        
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
        guard let email = GoogleAuthService.shared.userEmail?.lowercased(), !email.isEmpty else {
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
        
        // Prova a caricare da CloudKit
        do {
            if var cloudProfile = try await fetchProfile(email: email) {
                let (validated, wasRegenerated) = UserProfile.validatedUsername(cloudProfile.username, email: email)
                cloudProfile.username = validated
                if wasRegenerated {
                    try await saveProfile(cloudProfile)
                    print("[UserProfileService] Username non conforme, rigenerato e risincronizzato su CloudKit")
                }
                currentProfile = cloudProfile
                saveLocalProfile(cloudProfile)
            } else {
                // Crea nuovo profilo
                var newProfile = UserProfile(email: email)
                // Pre-popola nome da email se disponibile
                let parts = email.components(separatedBy: "@").first?.components(separatedBy: ".") ?? []
                if parts.count >= 2 {
                    newProfile.firstName = parts[0].capitalized
                    newProfile.lastName = parts[1].capitalized
                }
                currentProfile = newProfile
                try await saveProfile(newProfile)
            }
        } catch {
            self.error = error.localizedDescription
            print("[UserProfileService] ❌ refreshCurrentProfile: \(error)")
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
        try await saveProfile(profile)
    }
    
    /// Aggiorna un campo specifico del profilo
    func updateProfile(_ update: (inout UserProfile) -> Void) async throws {
        guard var profile = currentProfile else { return }
        update(&profile)
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalProfile(profile)
        try await saveProfile(profile)
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
    
    /// Refresh tutti i profili da CloudKit
    func refreshAllProfiles() async {
        do {
            let profiles = try await fetchAllProfiles()
            allProfiles = profiles
            saveAllProfilesLocal(profiles)
        } catch {
            print("[UserProfileService] ⚠️ refreshAllProfiles: \(error)")
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
        try await saveProfile(profile)
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
    
    // MARK: - CloudKit Operations
    
    private func fetchProfile(email: String) async throws -> UserProfile? {
        let recordID = CKRecord.ID(recordName: "profile_\(email)")
        
        do {
            let record = try await publicDB.record(for: recordID)
            return profileFromRecord(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
    
    private func fetchAllProfiles() async throws -> [UserProfile] {
        // Usa un predicato su un campo queryable invece di 'true' puro
        // che causa problemi con recordName non queryable
        let predicate = NSPredicate(format: "%K != %@", Keys.email, "")
        let query = CKQuery(recordType: RecordType.userProfile, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Keys.lastName, ascending: true)]
        
        let (results, _) = try await publicDB.records(matching: query, desiredKeys: nil, resultsLimit: 100)
        
        return results.compactMap { result -> UserProfile? in
            guard case .success(let record) = result.1 else { return nil }
            return profileFromRecord(record)
        }
    }
    
    private func saveProfile(_ profile: UserProfile) async throws {
        let recordID = CKRecord.ID(recordName: "profile_\(profile.email)")
        
        // Fetch o crea
        let record: CKRecord
        do {
            record = try await publicDB.record(for: recordID)
        } catch {
            record = CKRecord(recordType: RecordType.userProfile, recordID: recordID)
        }
        
        // Popola record
        record[Keys.email] = profile.email
        record[Keys.username] = profile.username
        record[Keys.firstName] = profile.firstName
        record[Keys.lastName] = profile.lastName
        record[Keys.birthDate] = profile.birthDate
        record[Keys.birthdayVisibility] = profile.birthdayVisibility.rawValue
        record[Keys.notifyBirthday] = profile.notifyBirthday ? 1 : 0
        record[Keys.avatarType] = profile.avatarType.rawValue
        record[Keys.generatedAvatarColor] = profile.generatedAvatar.backgroundColor
        record[Keys.generatedAvatarIcon] = profile.generatedAvatar.icon
        record[Keys.avatarGifURL] = profile.avatarGifURL
        record[Keys.contractType] = profile.contractType?.rawValue
        record[Keys.roles] = profile.roles.map { $0.rawValue }
        record[Keys.enableBadges] = profile.enableBadges ? 1 : 0
        record[Keys.sendReadReceipts] = profile.sendReadReceipts ? 1 : 0
        record[Keys.createdAt] = profile.createdAt
        record[Keys.updatedAt] = profile.updatedAt
        
        // Salva foto avatar come asset se presente
        if let photoData = profile.avatarPhotoData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try photoData.write(to: tempURL)
            record[Keys.avatarPhoto] = CKAsset(fileURL: tempURL)
        }
        
        _ = try await publicDB.save(record)
    }
    
    private func profileFromRecord(_ record: CKRecord) -> UserProfile? {
        guard let email = record[Keys.email] as? String else { return nil }
        
        var profile = UserProfile(email: email)
        
        profile.username = UserProfile.validatedUsername(record[Keys.username] as? String, email: email).0
        profile.firstName = (record[Keys.firstName] as? String) ?? ""
        profile.lastName = (record[Keys.lastName] as? String) ?? ""
        profile.birthDate = record[Keys.birthDate] as? Date
        
        if let visRaw = record[Keys.birthdayVisibility] as? String,
           let vis = BirthdayVisibility(rawValue: visRaw) {
            profile.birthdayVisibility = vis
        }
        
        profile.notifyBirthday = (record[Keys.notifyBirthday] as? Int ?? 1) == 1
        
        if let typeRaw = record[Keys.avatarType] as? String,
           let type = AvatarType(rawValue: typeRaw) {
            profile.avatarType = type
        }
        
        if let asset = record[Keys.avatarPhoto] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            profile.avatarPhotoData = data
        }
        
        if let color = record[Keys.generatedAvatarColor] as? String,
           let icon = record[Keys.generatedAvatarIcon] as? String {
            profile.generatedAvatar = GeneratedAvatar(backgroundColor: color, icon: icon)
        }
        
        profile.avatarGifURL = record[Keys.avatarGifURL] as? String
        
        if let contractRaw = record[Keys.contractType] as? String,
           let contract = ContractType(rawValue: contractRaw) {
            profile.contractType = contract
        }
        
        if let rolesRaw = record[Keys.roles] as? [String] {
            profile.roles = rolesRaw.compactMap { UserRole(rawValue: $0) }
        }
        
        profile.enableBadges = (record[Keys.enableBadges] as? Int ?? 0) == 1
        profile.sendReadReceipts = (record[Keys.sendReadReceipts] as? Int ?? 1) == 1
        profile.createdAt = (record[Keys.createdAt] as? Date) ?? Date()
        profile.updatedAt = (record[Keys.updatedAt] as? Date) ?? Date()
        
        return profile
    }
    
    // MARK: - Local Storage
    
    private func saveLocalProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadLocalProfile() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
        
        // Non caricare profilo se appartiene a un utente diverso da quello autenticato
        if let currentEmail = GoogleAuthService.shared.userEmail?.lowercased(),
           !currentEmail.isEmpty,
           profile.email.lowercased() != currentEmail {
            print("[UserProfileService] ⚠️ Profilo locale appartiene a utente diverso, ignorato")
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        
        let (validated, _) = UserProfile.validatedUsername(profile.username, email: profile.email)
        profile.username = validated
        currentProfile = profile
    }
    
    private func saveAllProfilesLocal(_ profiles: [UserProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: allProfilesKey)
        }
    }
    
    private func loadAllProfilesLocal() {
        guard let data = UserDefaults.standard.data(forKey: allProfilesKey),
              var profiles = try? JSONDecoder().decode([UserProfile].self, from: data) else { return }
        for i in profiles.indices {
            profiles[i].username = UserProfile.validatedUsername(profiles[i].username, email: profiles[i].email).0
        }
        allProfiles = profiles
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
}
