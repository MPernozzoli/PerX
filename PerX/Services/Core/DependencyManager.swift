import AppKit
import Combine
import Foundation
import OSLog

/// App-facing dependency facade. Discovery, monitoring, installation and
/// updates are delegated to the PerX Local Agent.
@MainActor
final class DependencyManager: ObservableObject {
    static let shared = DependencyManager()

    typealias Dependency = LocalDependency

    enum DependencyStatus {
        case installed(version: String?, updateAvailable: Bool?)
        case missing
        case checking
        case installing
        case updating
        case error(String)
    }

    /// PerX is distributed directly with Developer ID, outside App Store sandbox.
    static let isInSandbox = false

    @Published private(set) var statuses: [Dependency: DependencyStatus] = [:]
    @Published private(set) var isInstalling = false
    @Published private(set) var installationProgress = ""

    private let agent: any PerXLocalAgentClient
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "it.pernozzoli.PerX",
        category: "DependencyManager"
    )

    private init(agent: any PerXLocalAgentClient = PerXLocalAgent.shared) {
        self.agent = agent
        for dependency in Dependency.allCases {
            statuses[dependency] = .checking
        }

        Task {
            await checkAllDependencies()
            await agent.startDependencyMonitoring(interval: 60)
        }
    }

    func checkAllDependencies(checkForUpdates: Bool = false) async {
        for status in await agent.refreshDependencyStatuses(checkForUpdates: checkForUpdates) {
            statuses[status.dependency] = map(status)
        }
    }

    func checkDependency(_ dependency: Dependency, checkForUpdates: Bool = false) async {
        statuses[dependency] = .checking
        let status = await agent.dependencyStatus(dependency, checkForUpdates: checkForUpdates)
        statuses[dependency] = map(status)
    }

    func isDependencyInstalled(_ dependency: Dependency) async -> Bool {
        let status = await agent.dependencyStatus(dependency, checkForUpdates: false)
        statuses[dependency] = map(status)
        return status.isInstalled
    }

    func installDependency(_ dependency: Dependency) async -> Bool {
        isInstalling = true
        statuses[dependency] = .installing
        installationProgress = "Installazione \(dependency.displayName) in corso..."
        defer { isInstalling = false }

        do {
            let status = try await agent.installDependency(dependency)
            statuses[dependency] = map(status)
            installationProgress = "\(dependency.displayName) installato con successo"
            NotificationService.shared.sendNotification(
                title: "Installazione completata",
                body: "\(dependency.displayName) e stato installato correttamente"
            )
            return status.isInstalled
        } catch {
            statuses[dependency] = .error(error.localizedDescription)
            installationProgress = "Errore durante l'installazione di \(dependency.displayName)"
            logger.error("event=dependency_install_failed dependency=\(dependency.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            if let url = dependency.installationURL {
                NSWorkspace.shared.open(url)
            }
            return false
        }
    }

    func updateDependency(_ dependency: Dependency) async -> Bool {
        statuses[dependency] = .updating
        installationProgress = "Aggiornamento \(dependency.displayName) in corso..."

        do {
            let status = try await agent.updateDependency(dependency)
            statuses[dependency] = map(status)
            installationProgress = "\(dependency.displayName) aggiornato con successo"
            return status.isInstalled
        } catch {
            statuses[dependency] = .error(error.localizedDescription)
            installationProgress = "Errore durante l'aggiornamento di \(dependency.displayName)"
            logger.error("event=dependency_update_failed dependency=\(dependency.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func handleServiceError(_ error: Error, for dependency: Dependency) async {
        logger.error("event=dependency_consumer_failed dependency=\(dependency.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        guard !(await isDependencyInstalled(dependency)) else { return }

        NotificationService.shared.sendNotification(
            title: "Dipendenza mancante",
            body: "Installazione automatica di \(dependency.displayName) in corso..."
        )
        _ = await installDependency(dependency)
    }

    private func map(_ status: LocalDependencyStatus) -> DependencyStatus {
        switch status.state {
        case .installed:
            return .installed(version: status.version, updateAvailable: status.updateAvailable)
        case .missing:
            return .missing
        case .installing:
            return .installing
        case .updating:
            return .updating
        case .error:
            return .error(status.message ?? "Errore dipendenza locale")
        }
    }
}
