import SwiftUI
import AppKit

// Color(hex:) extension è in Extensions/Color+Extensions.swift

// MARK: - Avatar View (Riutilizzabile)

/// Vista avatar che mostra foto profilo, avatar generato o iniziali
struct AvatarView: View {
    let profile: UserProfile?
    var size: CGFloat = 40
    var showOnlineStatus: Bool = false
    var onlineStatus: CloudKitUserDirectoryService.OnlineStatus? = nil
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
            
            if showOnlineStatus, let status = onlineStatus {
                Circle()
                    .fill(Color(status.color))
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(
                        Circle()
                            .stroke(Color(.controlBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
    
    @ViewBuilder
    private var avatarContent: some View {
        if let profile = profile {
            switch profile.avatarType {
            case .photo:
                if let image = profile.avatarImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    generatedAvatarView(profile.generatedAvatar, initials: initials(from: profile))
                }
                
            case .generated:
                generatedAvatarView(profile.generatedAvatar, initials: initials(from: profile))
                
            case .gif:
                // TODO: Supporto GIF animate
                generatedAvatarView(profile.generatedAvatar, initials: initials(from: profile))
            }
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.gray)
                }
        }
    }
    
    private func generatedAvatarView(_ avatar: GeneratedAvatar, initials: String) -> some View {
        Circle()
            .fill(Color(hex: avatar.backgroundColor))
            .overlay {
                if initials.isEmpty {
                    Image(systemName: avatar.icon)
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.35, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
    }
    
    private func initials(from profile: UserProfile) -> String {
        let first = profile.firstName.prefix(1).uppercased()
        let last = profile.lastName.prefix(1).uppercased()
        if first.isEmpty && last.isEmpty {
            return ""
        }
        return "\(first)\(last)"
    }
}

// MARK: - Avatar View from Email

/// Vista avatar che recupera automaticamente il profilo dall'email
struct AvatarFromEmailView: View {
    let email: String
    var size: CGFloat = 40
    var fallbackName: String? = nil
    var showOnlineStatus: Bool = false
    
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var userDirectory = CloudKitUserDirectoryService.shared
    
    private var profile: UserProfile? {
        profileService.profile(for: email)
    }
    
    private var cloudUser: CloudKitUserDirectoryService.CloudUser? {
        userDirectory.user(email: email)
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let profile = profile {
                AvatarView(profile: profile, size: size)
            } else {
                // Fallback: avatar generato dalle iniziali del nome
                fallbackAvatar
            }
            
            if showOnlineStatus, let user = cloudUser {
                Circle()
                    .fill(Color(user.onlineStatus.color))
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(
                        Circle()
                            .stroke(Color(.controlBackgroundColor), lineWidth: 2)
                    )
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
    
    private var fallbackAvatar: some View {
        let name = fallbackName ?? cloudUser?.displayName ?? email.components(separatedBy: "@").first ?? "?"
        let initials = String(name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased()
        
        return Circle()
            .fill(avatarColor(for: email))
            .frame(width: size, height: size)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.35, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
    }
    
    private func avatarColor(for email: String) -> Color {
        // Genera un colore consistente basato sull'email
        let colors: [Color] = [
            .blue, .purple, .green, .orange, .pink, .teal, .indigo, .cyan
        ]
        let hash = abs(email.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Display Name Helper

/// Helper per ottenere il nome visualizzato di un utente
@MainActor
struct UserDisplayNameHelper {
    static func displayName(for email: String, fallbackName: String? = nil) -> String {
        // Prima cerca nel profilo
        if let profile = UserProfileService.shared.profile(for: email) {
            return profile.displayName
        }
        
        // Poi cerca nella directory CloudKit
        if let cloudUser = CloudKitUserDirectoryService.shared.user(email: email) {
            return cloudUser.displayName
        }
        
        // Fallback al nome passato o generato dall'email
        if let fallback = fallbackName, !fallback.isEmpty {
            return fallback
        }
        
        return email.components(separatedBy: "@").first?
            .replacingOccurrences(of: ".", with: " ")
            .capitalized ?? email
    }
}
