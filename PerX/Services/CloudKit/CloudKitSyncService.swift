import Combine
import CoreData
import Foundation

@MainActor
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    enum Status: Equatable {
        case idle
        case ready
        case syncing(String)
        case unavailable(String)
        case error(String)
    }

    @Published private(set) var status: Status = .unavailable("CloudKit disabled; backend Supabase is authoritative")
    @Published private(set) var lastSyncAt: Date?

    private init() {}

    func startIfEnabled(email: String?) {
        status = .ready
    }

    func configureCurrentUser(email: String?) {
        status = .ready
    }

    func syncNow(reason: String = "manual") async {
        status = .ready
        lastSyncAt = Date()
    }

    func startIfEnabled(context: NSManagedObjectContext) async {
        status = .ready
    }

    func syncNow(context: NSManagedObjectContext) async {
        await syncNow(reason: "manual")
    }

    func stop() {
        status = .idle
    }
}
