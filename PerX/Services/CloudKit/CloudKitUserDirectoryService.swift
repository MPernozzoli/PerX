import Foundation
import Combine
import AppKit

/// Directory utenti compatibile con le viste esistenti, alimentata dal backend Supabase.
@MainActor
final class CloudKitUserDirectoryService: ObservableObject {
    static let shared = CloudKitUserDirectoryService()

    enum OnlineStatus: String, Codable {
        case online
        case recent
        case offline

        var color: NSColor {
            switch self {
            case .online: return .systemGreen
            case .recent: return .systemYellow
            case .offline: return .systemRed
            }
        }

        var label: String {
            switch self {
            case .online: return "Online"
            case .recent: return "Visto di recente"
            case .offline: return "Offline"
            }
        }
    }

    enum WorkLocation: String, Codable {
        case office
        case remote
        case notWorking

        var icon: String {
            switch self {
            case .office: return "building.2.fill"
            case .remote: return "house.fill"
            case .notWorking: return "moon.zzz.fill"
            }
        }

        var label: String {
            switch self {
            case .office: return "In ufficio"
            case .remote: return "Da remoto"
            case .notWorking: return "Non lavora oggi"
            }
        }
    }

    struct CloudUser: Identifiable, Codable, Equatable {
        var id: String { email }
        let email: String
        let displayName: String
        let lastSeenAt: Date
        var workScheduleToday: String?
        var workLocation: WorkLocation?
        var isComputerActive: Bool
        var backendUserId: String?

        init(
            email: String,
            displayName: String,
            lastSeenAt: Date,
            workScheduleToday: String? = nil,
            workLocation: WorkLocation? = nil,
            isComputerActive: Bool = false,
            backendUserId: String? = nil
        ) {
            self.email = email
            self.displayName = displayName
            self.lastSeenAt = lastSeenAt
            self.workScheduleToday = workScheduleToday
            self.workLocation = workLocation
            self.isComputerActive = isComputerActive
            self.backendUserId = backendUserId
        }

        var onlineStatus: OnlineStatus {
            let diff = Date().timeIntervalSince(lastSeenAt)
            if isComputerActive && diff < 120 { return .online }
            if diff < 15 * 60 { return .recent }
            return .offline
        }
    }

    @Published private(set) var users: [CloudUser] = []
    @Published private(set) var status: String = "idle"
    @Published private(set) var typingIndicators: [String: [String: Date]] = [:]

    private var timer: Timer?
    private let client = BackendAPIClient.shared

    private init() {}

    func start() async {
        await refreshNow(reason: "start")
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        status = "stopped"
        typingIndicators.removeAll()
    }

    func setTyping(in roomId: String) async {
        guard let email = CurrentUserService.shared.currentEmail?.lowercased() else { return }
        var roomTyping = typingIndicators[roomId] ?? [:]
        roomTyping[email] = Date()
        typingIndicators[roomId] = roomTyping
    }

    func fetchTypingUsers(in roomId: String) async -> [CloudUser] {
        let threshold = Date().addingTimeInterval(-15)
        let emails = (typingIndicators[roomId] ?? [:])
            .filter { $0.value > threshold }
            .map(\.key)
        return emails.compactMap { user(email: $0) }
    }

    func clearTyping(in roomId: String) async {
        guard let email = CurrentUserService.shared.currentEmail?.lowercased() else { return }
        typingIndicators[roomId]?[email] = nil
    }

    func refreshNow(reason: String) async {
        guard client.isConfigured, client.hasAccessToken else {
            loadFromProfilesCache()
            status = "local"
            return
        }

        status = "syncing"
        do {
            let response: UserDirectoryListDTO = try await client.get("user-directory")
            users = response.items.map { $0.toCloudUser() }
            status = "ok"
            await updatePresence()
        } catch {
            print("[UserDirectory] backend refresh failed: \(error)")
            loadFromProfilesCache()
            status = "error"
        }
    }

    func user(email: String) -> CloudUser? {
        let normalized = email.lowercased()
        return users.first { $0.email.lowercased() == normalized }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refreshNow(reason: "timer") }
        }
    }

    private func updatePresence() async {
        guard client.isConfigured, client.hasAccessToken else { return }
        let location = currentWorkLocation()
        do {
            let _: UserDirectoryEntryDTO = try await client.put(
                "user-directory/me/presence",
                body: PresenceUpdateDTO(location: location?.rawValue)
            )
        } catch {
            print("[UserDirectory] backend presence update failed: \(error)")
        }
    }

    private func loadFromProfilesCache() {
        let profiles = UserProfileService.shared.allProfiles
        if !profiles.isEmpty {
            users = profiles.map {
                CloudUser(
                    email: $0.email,
                    displayName: $0.displayName,
                    lastSeenAt: Date.distantPast,
                    isComputerActive: false
                )
            }
        } else if let email = CurrentUserService.shared.currentEmail {
            users = [
                CloudUser(
                    email: email,
                    displayName: UserProfileService.shared.currentProfile?.displayName ?? CurrentUserService.shared.currentUsernameOrDefault(email),
                    lastSeenAt: Date(),
                    isComputerActive: true
                )
            ]
        }
    }

    private func currentWorkLocation() -> WorkLocation? {
        let today = Calendar.current.component(.weekday, from: Date())
        guard let schedule = WorkScheduleManager.shared.weekdaySchedules[today], schedule.isWorkingDay else {
            return .notWorking
        }
        return .office
    }
}

private struct UserDirectoryListDTO: Codable {
    let items: [UserDirectoryEntryDTO]
    let total: Int
}

private struct UserDirectoryEntryDTO: Codable {
    let id: String
    let email: String
    let full_name: String?
    let first_name: String?
    let last_name: String?
    let job_title: String?
    let is_active: Bool
    let last_seen_at: Date?
    let work_location: String?

    func toCloudUser() -> CloudKitUserDirectoryService.CloudUser {
        let display = full_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = [first_name, last_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return CloudKitUserDirectoryService.CloudUser(
            email: email.lowercased(),
            displayName: (display?.isEmpty == false ? display! : fallback.isEmpty ? email : fallback),
            lastSeenAt: last_seen_at ?? Date.distantPast,
            workLocation: work_location.flatMap(CloudKitUserDirectoryService.WorkLocation.init(rawValue:)),
            isComputerActive: last_seen_at.map { Date().timeIntervalSince($0) < 120 } ?? false,
            backendUserId: id
        )
    }
}

private struct PresenceUpdateDTO: Codable {
    let location: String?
}
