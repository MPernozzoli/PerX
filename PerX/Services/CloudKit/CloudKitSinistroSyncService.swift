import Combine
import CoreData
import Foundation

@MainActor
final class CloudKitSinistroSyncService: ObservableObject {
    static let shared = CloudKitSinistroSyncService()

    struct SyncError: Identifiable, Hashable {
        enum ErrorType: String {
            case info
            case backend
        }

        let id = UUID()
        let type: ErrorType
        let message: String
        let details: String?
        let context: String?
        let timestamp: Date

        var fullDescription: String {
            [type.rawValue, message, details, context]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
        }
    }

    @Published private(set) var downloadsInProgress = 0
    @Published private(set) var uploadsInProgress = 0
    @Published private(set) var pendingChanges = 0
    @Published private(set) var errors: [SyncError] = []
    @Published private(set) var lastMinimalSyncCount = 0
    @Published private(set) var totalMinimalProcessed = 0
    @Published private(set) var totalMinimalUploaded = 0
    @Published private(set) var totalFullUploaded = 0
    @Published private(set) var lastOwnedFullUploadCount = 0
    @Published private(set) var lastSyncAt: Date?

    private init() {}

    func syncNow(reason: String = "manual") async {
        lastSyncAt = Date()
    }

    func startBackgroundSync(context: NSManagedObjectContext) {}
    func stopBackgroundSync() {}
    func clearErrors() { errors.removeAll() }
}
