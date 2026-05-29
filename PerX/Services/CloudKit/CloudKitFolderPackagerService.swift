import Combine
import Foundation

@MainActor
final class CloudKitFolderPackagerService: ObservableObject {
    static let shared = CloudKitFolderPackagerService()

    @Published private(set) var isRunning = false

    private init() {}

    func start() {
        isRunning = false
    }

    func stop() {
        isRunning = false
    }
}
