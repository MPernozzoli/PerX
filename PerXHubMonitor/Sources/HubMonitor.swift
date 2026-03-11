import Foundation
import Combine
import AppKit

/// Monitor che interroga l'Hub e tutti i servizi periodicamente
class HubMonitor: ObservableObject {
    // MARK: - Published State
    
    @Published var isOnline = false
    @Published var lastCheck: Date?
    @Published var health: HealthStatus?
    @Published var pendingJobs: [JobInfo] = []
    @Published var recentEmails: Int = 0
    @Published var pendingAttachments: Int = 0
    @Published var error: String?
    @Published var isLoading = false
    
    // Stats
    @Published var emailStats: EmailStats?
    @Published var jobStats: JobStats?
    @Published var whatsappStats: WhatsAppStats?
    @Published var syncStats: SyncStats?
    @Published var chromeExtStats: ChromeExtStats?
    @Published var sinistriCount: Int = 0
    
    // Multi-service monitoring
    @Published var services: [ServiceStatus] = []
    @Published var connectedUsers: Int = 0
    
    // Aggiornamenti disponibili
    @Published var pendingUpdates: [String: [String]] = [:]  // component -> [changedFiles]
    
    // MARK: - Configuration
    
    var hubURL: String {
        get { UserDefaults.standard.string(forKey: "hubURL") ?? "http://localhost:8080" }
        set { UserDefaults.standard.set(newValue, forKey: "hubURL") }
    }
    
    var mailWorkerURL: String {
        get { UserDefaults.standard.string(forKey: "mailWorkerURL") ?? "http://localhost:5001" }
        set { UserDefaults.standard.set(newValue, forKey: "mailWorkerURL") }
    }
    
    var waBridgeURL: String {
        get { UserDefaults.standard.string(forKey: "waBridgeURL") ?? "http://localhost:5002" }
        set { UserDefaults.standard.set(newValue, forKey: "waBridgeURL") }
    }
    
    var syncAgentURL: String {
        get { UserDefaults.standard.string(forKey: "syncAgentURL") ?? "https://perx-sync-agent.tailca58be.ts.net" }
        set { UserDefaults.standard.set(newValue, forKey: "syncAgentURL") }
    }
    
    var autoUpdaterURL: String {
        get { UserDefaults.standard.string(forKey: "autoUpdaterURL") ?? "http://localhost:8084" }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdaterURL") }
    }
    
    var vaultPath: String {
        get { UserDefaults.standard.string(forKey: "vaultPath") ?? "/opt/perx-hub/vault/sinistri" }
        set { UserDefaults.standard.set(newValue, forKey: "vaultPath") }
    }
    
    var pollingInterval: TimeInterval = 30 // secondi
    
    // MARK: - Internal
    
    var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let launchctl = LaunchctlManager()
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        // Prima chiamata immediata
        Task {
            await refresh()
        }
        
        // Timer per polling periodico
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refresh()
            }
        }
    }
    
    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    @MainActor
    func refresh() async {
        isLoading = true
        error = nil
        
        // Refresh tutti i servizi in parallelo
        await refreshAllServices()
        
        // Health check Hub
        do {
            health = try await fetchHealth()
            isOnline = true
            lastCheck = Date()
        } catch {
            isOnline = false
            self.error = error.localizedDescription
        }
        
        // Se online, carica altri dati
        if isOnline {
            do {
                pendingJobs = try await fetchPendingJobs()
                
                // Usa endpoint /stats per statistiche complete
                if let stats = try await fetchStats() {
                    emailStats = EmailStats(
                        totalProcessed: stats.emails.total,
                        todayProcessed: stats.emails.total,
                        pendingSync: stats.emails.unsynced
                    )
                    pendingAttachments = stats.attachments.pending + stats.attachments.processing
                    jobStats = JobStats(
                        pending: stats.jobs.pending,
                        inProgress: stats.jobs.inProgress,
                        completedToday: 0,
                        failedToday: 0
                    )
                    connectedUsers = stats.connectedUsers ?? 0
                    
                    // WhatsApp stats
                    if let wa = stats.whatsapp {
                        whatsappStats = WhatsAppStats(
                            totalMessages: wa.totalMessages,
                            todayMessages: wa.todayMessages,
                            unreadChats: wa.unreadChats,
                            scheduledPending: wa.scheduledPending
                        )
                    }
                    
                    // Sync stats
                    if let sync = stats.sync {
                        syncStats = SyncStats(
                            activeFolders: sync.activeFolders,
                            pendingSyncs: sync.pendingSyncs,
                            lastSyncAt: sync.lastSyncAt
                        )
                    }
                    
                    // Chrome Extension stats
                    if let chrome = stats.chromeExt {
                        chromeExtStats = ChromeExtStats(
                            todayDiarioEntries: chrome.todayDiarioEntries,
                            todayJFishSyncs: chrome.todayJFishSyncs
                        )
                    }
                    
                    // Sinistri count
                    sinistriCount = stats.sinistri
                }
            } catch {
                print("[Monitor] Failed to fetch details: \(error)")
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Multi-Service Monitoring
    
    @MainActor
    private func refreshAllServices() async {
        var newServices: [ServiceStatus] = []
        
        // Hub
        let hubStatus = await checkServiceHealth(
            id: "hub",
            name: "PerX Hub",
            url: hubURL,
            restartMethod: .launchctl("com.perx.hub")
        )
        newServices.append(hubStatus)
        
        // Mail Worker
        if !mailWorkerURL.isEmpty {
            let mailStatus = await checkServiceHealth(
                id: "mail",
                name: "Mail Worker",
                url: mailWorkerURL,
                restartMethod: .launchctl("com.perx.email-worker")
            )
            newServices.append(mailStatus)
        }
        
        // WA Bridge
        if !waBridgeURL.isEmpty {
            let waStatus = await checkServiceHealth(
                id: "wa",
                name: "WA Bridge",
                url: waBridgeURL,
                restartMethod: .launchctl("com.perx.wa-bridge")
            )
            newServices.append(waStatus)
        }
        
        // SyncAgent Windows
        if !syncAgentURL.isEmpty {
            let syncStatus = await checkServiceHealth(
                id: "sync",
                name: "SyncAgent Win",
                url: syncAgentURL,
                restartMethod: .api("\(syncAgentURL)/restart")
            )
            newServices.append(syncStatus)
        }
        
        // AutoUpdater
        if !autoUpdaterURL.isEmpty {
            let updaterStatus = await checkServiceHealth(
                id: "updater",
                name: "AutoUpdater",
                url: autoUpdaterURL,
                restartMethod: .launchctl("com.perx.autoupdater")
            )
            newServices.append(updaterStatus)
        }
        
        services = newServices
        
        // Recupera aggiornamenti pendenti dall'Hub
        await fetchPendingUpdates()
    }
    
    // MARK: - Updates
    
    @MainActor
    private func fetchPendingUpdates() async {
        guard isOnline else { return }
        
        guard let url = URL(string: "\(hubURL)/internal/updates") else { return }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            
            pendingUpdates = try decoder.decode([String: [String]].self, from: data)
        } catch {
            print("[Monitor] Failed to fetch updates: \(error)")
        }
    }
    
    /// Conferma che l'aggiornamento è stato applicato
    @MainActor
    func acknowledgeUpdate(for component: String) async {
        guard let url = URL(string: "\(hubURL)/internal/updates/ack") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["component": component])
        
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                pendingUpdates.removeValue(forKey: component)
            }
        } catch {
            print("[Monitor] Failed to ack update: \(error)")
        }
    }
    
    /// Verifica se c'è un aggiornamento per un servizio
    func hasUpdate(for serviceId: String) -> Bool {
        let componentMap = [
            "hub": "perx_hub",
            "mail": "perx_email_worker",
            "wa": "perx_wa_bridge",
            "sync": "perx_sync_agent",
            "updater": "perx_autoupdater"
        ]
        
        guard let componentName = componentMap[serviceId] else { return false }
        return pendingUpdates[componentName] != nil && !(pendingUpdates[componentName]?.isEmpty ?? true)
    }
    
    /// Restituisce il nome componente dall'ID servizio
    func componentName(for serviceId: String) -> String? {
        let componentMap = [
            "hub": "perx_hub",
            "mail": "perx_email_worker",
            "wa": "perx_wa_bridge",
            "sync": "perx_sync_agent",
            "updater": "perx_autoupdater"
        ]
        return componentMap[serviceId]
    }
    
    private func checkServiceHealth(
        id: String,
        name: String,
        url: String,
        restartMethod: RestartMethod
    ) async -> ServiceStatus {
        guard let healthURL = URL(string: "\(url)/health") else {
            return ServiceStatus(id: id, name: name, isOnline: false, version: nil, uptime: nil, restartMethod: restartMethod, error: "URL non valido")
        }
        
        do {
            let (data, response) = try await session.data(from: healthURL)
            
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ServiceStatus(id: id, name: name, isOnline: false, version: nil, uptime: nil, restartMethod: restartMethod, error: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            // Prova a decodificare health response
            if let health = try? decoder.decode(ServiceHealthResponse.self, from: data) {
                return ServiceStatus(
                    id: id,
                    name: name,
                    isOnline: true,
                    version: health.version,
                    uptime: health.uptime,
                    restartMethod: restartMethod,
                    error: nil
                )
            }
            
            return ServiceStatus(id: id, name: name, isOnline: true, version: nil, uptime: nil, restartMethod: restartMethod, error: nil)
        } catch {
            return ServiceStatus(id: id, name: name, isOnline: false, version: nil, uptime: nil, restartMethod: restartMethod, error: error.localizedDescription)
        }
    }
    
    // MARK: - Restart Services
    
    @MainActor
    func restartService(_ service: ServiceStatus) async -> Bool {
        switch service.restartMethod {
        case .launchctl(let identifier):
            return await launchctl.restart(identifier: identifier)
        case .api(let url):
            return await restartViaAPI(url: url)
        }
    }
    
    private func restartViaAPI(url: String) async -> Bool {
        guard let restartURL = URL(string: url) else { return false }
        
        var request = URLRequest(url: restartURL)
        request.httpMethod = "POST"
        
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode >= 200 && http.statusCode < 300
            }
            return false
        } catch {
            print("[Monitor] Restart API failed: \(error)")
            return false
        }
    }
    
    @MainActor
    func restartMonitor() {
        // Riavvia l'app stessa
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open -n '\(Bundle.main.bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil as Any?)
    }
    
    // MARK: - API Calls
    
    private func fetchHealth() async throws -> HealthStatus {
        let url = URL(string: "\(hubURL)/health")!
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MonitorError.invalidResponse
        }
        
        return try decoder.decode(HealthStatus.self, from: data)
    }
    
    private func fetchPendingJobs() async throws -> [JobInfo] {
        let url = URL(string: "\(hubURL)/jobs/pending")!
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        
        return try decoder.decode([JobInfo].self, from: data)
    }
    
    private func fetchStats() async throws -> HubStats? {
        let url = URL(string: "\(hubURL)/stats")!
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        
        return try decoder.decode(HubStats.self, from: data)
    }
}

// MARK: - Models

struct HealthStatus: Codable {
    let status: String
    let version: String
    let uptime: TimeInterval
    let timestamp: Date
    
    var uptimeFormatted: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)g \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

struct JobInfo: Codable, Identifiable {
    let id: String
    let type: String
    let status: String
    let priority: Int
    let createdAt: Date
    
    var typeIcon: String {
        switch type {
        case "import_folder": return "arrow.down.doc"
        case "export_file": return "arrow.up.doc"
        case "scan_legacy": return "magnifyingglass"
        case "delete_file": return "trash"
        case "rename_file": return "pencil"
        default: return "doc"
        }
    }
    
    var typeDisplayName: String {
        switch type {
        case "import_folder": return "Import"
        case "export_file": return "Export"
        case "scan_legacy": return "Scan"
        case "delete_file": return "Elimina"
        case "rename_file": return "Rinomina"
        default: return type
        }
    }
}

struct EmailStats: Codable {
    let totalProcessed: Int
    let todayProcessed: Int
    let pendingSync: Int
}

struct JobStats: Codable {
    let pending: Int
    let inProgress: Int
    let completedToday: Int
    let failedToday: Int
}

struct WhatsAppStats: Codable {
    let totalMessages: Int
    let todayMessages: Int
    let unreadChats: Int
    let scheduledPending: Int
}

struct SyncStats: Codable {
    let activeFolders: Int
    let pendingSyncs: Int
    let lastSyncAt: Date?
}

struct ChromeExtStats: Codable {
    let todayDiarioEntries: Int
    let todayJFishSyncs: Int
}

enum MonitorError: Error {
    case invalidResponse
    case notReachable
}

/// Stats complete dall'Hub (rispecchia HubStatsResponse)
struct HubStats: Codable {
    let jobs: JobStatsResponse
    let emails: EmailStatsResponse
    let attachments: AttachmentStatsResponse
    let whatsapp: WhatsAppStatsResponse?
    let sync: SyncStatsResponse?
    let chromeExt: ChromeExtStatsResponse?
    let sinistri: Int
    let uptime: TimeInterval
    let connectedUsers: Int?
    
    struct JobStatsResponse: Codable {
        let pending: Int
        let inProgress: Int
    }
    
    struct EmailStatsResponse: Codable {
        let total: Int
        let unsynced: Int
    }
    
    struct AttachmentStatsResponse: Codable {
        let pending: Int
        let processing: Int
    }
    
    struct WhatsAppStatsResponse: Codable {
        let totalMessages: Int
        let todayMessages: Int
        let unreadChats: Int
        let scheduledPending: Int
    }
    
    struct SyncStatsResponse: Codable {
        let activeFolders: Int
        let pendingSyncs: Int
        let lastSyncAt: Date?
    }
    
    struct ChromeExtStatsResponse: Codable {
        let todayDiarioEntries: Int
        let todayJFishSyncs: Int
    }
}

// MARK: - Multi-Service Models

struct ServiceStatus: Identifiable {
    let id: String
    let name: String
    let isOnline: Bool
    let version: String?
    let uptime: TimeInterval?
    let restartMethod: RestartMethod
    let error: String?
    
    var uptimeFormatted: String? {
        guard let uptime = uptime else { return nil }
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)g \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

enum RestartMethod {
    case launchctl(String)  // Identifier del servizio launchd
    case api(String)        // URL dell'API restart
}

struct ServiceHealthResponse: Codable {
    let status: String?
    let version: String?
    let uptime: TimeInterval?
}

// MARK: - Launchctl Manager

class LaunchctlManager {
    func restart(identifier: String) async -> Bool {
        let uid = getuid()
        let command = "launchctl kickstart -k gui/\(uid)/\(identifier)"
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", command]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            do {
                try task.run()
            } catch {
                print("[Launchctl] Failed to run: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
}
