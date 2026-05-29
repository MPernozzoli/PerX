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
    
    var waBridgeURL: String {
        get { UserDefaults.standard.string(forKey: "waBridgeURL") ?? "http://localhost:5002" }
        set { UserDefaults.standard.set(newValue, forKey: "waBridgeURL") }
    }
    
    var autoUpdaterURL: String {
        get { UserDefaults.standard.string(forKey: "autoUpdaterURL") ?? "http://localhost:8084" }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdaterURL") }
    }
    
    var vaultPath: String {
        get { UserDefaults.standard.string(forKey: "vaultPath") ?? "/opt/perx-hub/vault/sinistri" }
        set { UserDefaults.standard.set(newValue, forKey: "vaultPath") }
    }
    
    /// Directory installazione Hub sul Mini (per `data/monitor-secrets.json`)
    var hubInstallBasePath: String {
        get { UserDefaults.standard.string(forKey: "hubInstallBasePath") ?? "/opt/perx-hub" }
        set { UserDefaults.standard.set(newValue, forKey: "hubInstallBasePath") }
    }
    
    var pollingInterval: TimeInterval = 30 // secondi
    
    // MARK: - Segreti Hub (file scritto per il daemon)
    
    var monitorSecretsFilePath: String {
        "\(hubInstallBasePath)/data/monitor-secrets.json"
    }
    
    /// Legge `monitor-secrets.json` se presente (per riempire le impostazioni).
    func loadMonitorSecretsForEditor() -> (supabaseURL: String, serviceRoleKey: String, storageToken: String) {
        let path = monitorSecretsFilePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let decoded = try? JSONDecoder().decode(HubMonitorRuntimeSecrets.self, from: data) else {
            return ("", "", "")
        }
        return (
            decoded.supabaseURL ?? "",
            decoded.supabaseServiceRoleKey ?? "",
            decoded.storageSharedSecret ?? ""
        )
    }
    
    /// Salva i segreti sul disco; il daemon Hub va riavviato per applicarli.
    func saveMonitorSecrets(supabaseURL: String, serviceRoleKey: String, storageToken: String) throws {
        let path = monitorSecretsFilePath
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        let url = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = serviceRoleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = storageToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let payload = HubMonitorRuntimeSecrets(
            supabaseURL: url.isEmpty ? nil : url,
            supabaseServiceRoleKey: role.isEmpty ? nil : role,
            storageSharedSecret: tok.isEmpty ? nil : tok
        )
        
        if payload.supabaseURL == nil, payload.supabaseServiceRoleKey == nil, payload.storageSharedSecret == nil {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            return
        }
        
        let data = try JSONEncoder().encode(payload)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: path
        )
    }
    
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
            "wa": "perx_wa_bridge",
            "updater": "perx_autoupdater"
        ]
        
        guard let componentName = componentMap[serviceId] else { return false }
        return pendingUpdates[componentName] != nil && !(pendingUpdates[componentName]?.isEmpty ?? true)
    }
    
    /// Restituisce il nome componente dall'ID servizio
    func componentName(for serviceId: String) -> String? {
        let componentMap = [
            "hub": "perx_hub",
            "wa": "perx_wa_bridge",
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
    
    /// Riavvio daemon Hub (`com.perx.hub`); compare dialog password amministratore.
    @MainActor
    func restartPerxHubDaemon() async -> Bool {
        await launchctl.restart(identifier: "com.perx.hub")
    }
    
    /// Allinea `EnvironmentVariables` di `/Library/LaunchDaemons/com.perx.hub.plist` a ciò che salvi nel Monitor
    /// (altrimenti l’Hub continua a leggere il plist vecchio). Rimuove chiavi obsolete tipo `PERX_SYNC_AGENT_URL`.
    @MainActor
    func syncHubLaunchDaemonPlistEnvironment(
        waBridgeURL: String,
        autoUpdaterURL: String,
        hubInstallBasePath: String
    ) async -> String? {
        let scriptBody = Self.bashScriptHubPlistSync(
            waBridgeURL: waBridgeURL,
            autoUpdaterURL: autoUpdaterURL,
            hubInstallBasePath: hubInstallBasePath
        )
        let b64 = Data(scriptBody.utf8).base64EncodedString()
        let appleScript = """
        do shell script "echo \(b64) | base64 -d | /bin/bash" with administrator privileges
        """
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]
            let errPipe = Pipe()
            task.standardError = errPipe
            task.terminationHandler = { process in
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: nil)
                } else {
                    let msg = err.isEmpty ? "osascript exit \(process.terminationStatus)" : err
                    continuation.resume(returning: msg)
                }
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: error.localizedDescription)
            }
        }
    }
    
    private static func bashSingleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
   
    private static func bashScriptHubPlistSync(
        waBridgeURL: String,
        autoUpdaterURL: String,
        hubInstallBasePath: String
    ) -> String {
        let w = bashSingleQuoted(waBridgeURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let a = bashSingleQuoted(autoUpdaterURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let h = bashSingleQuoted(hubInstallBasePath.trimmingCharacters(in: .whitespacesAndNewlines))
        // In raw `#"""` le interpolazioni sono `\#(...)`; `\\(...)` finirebbe letterale in bash e rompe con `)`.
        return #"""
        set -e
        PLIST='/Library/LaunchDaemons/com.perx.hub.plist'
        pb_set() {
          local k="$1"
          local v="$2"
          /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:$k $v" "$PLIST" 2>/dev/null || \
          /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:$k string $v" "$PLIST"
        }
        pb_del() {
          local k="$1"
          /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$k" "$PLIST" 2>/dev/null || true
        }
        pb_set PERX_WA_BRIDGE_URL \#(w)
        pb_set PERX_AUTO_UPDATER_URL \#(a)
        pb_set PERX_HUB_PATH \#(h)
        pb_del PERX_EMAIL_WORKER_URL
        pb_del PERX_SYNC_AGENT_URL
        exit 0
        """#
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
    /// I LaunchDaemon PerX sono nel dominio `system/`; serve `sudo` → AppleScript chiede password admin.
    func restart(identifier: String) async -> Bool {
        let escaped = identifier.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"launchctl kickstart -k system/\(escaped)\" with administrator privileges"
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            do {
                try task.run()
            } catch {
                print("[Launchctl] Failed to run osascript: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Stesso JSON di PerXHub `monitor-secrets.json`

private struct HubMonitorRuntimeSecrets: Codable {
    var supabaseURL: String?
    var supabaseServiceRoleKey: String?
    var storageSharedSecret: String?
}
