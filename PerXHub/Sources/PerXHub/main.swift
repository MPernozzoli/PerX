import Foundation
import Vapor
import PerXCore

// MARK: - Configuration

struct HubConfiguration {
    static let version = "1.0.0"
    
    // Paths - default per development, override con env vars
    static var basePath: String {
        ProcessInfo.processInfo.environment["PERX_HUB_PATH"] ?? "/opt/perx-hub"
    }
    
    static var vaultPath: String { "\(basePath)/vault" }
    static var dataPath: String { "\(basePath)/data" }
    static var logsPath: String { "\(basePath)/logs" }
    static var dbPath: String { "\(dataPath)/vault.sqlite" }
    static var hubID: String {
        ProcessInfo.processInfo.environment["PERX_HUB_ID"] ?? Host.current().localizedName ?? "perx-hub"
    }
    static var defaultTenantSlug: String {
        ProcessInfo.processInfo.environment["PERX_DEFAULT_TENANT"] ?? "default"
    }
    static var dedicatedTenantSlug: String {
        ProcessInfo.processInfo.environment["PERX_DEDICATED_TENANT"] ?? defaultTenantSlug
    }
    
    // Server
    static var hostname: String {
        ProcessInfo.processInfo.environment["PERX_HUB_HOST"] ?? "0.0.0.0"
    }
    
    static var port: Int {
        Int(ProcessInfo.processInfo.environment["PERX_HUB_PORT"] ?? "8080") ?? 8080
    }
    
    // Repository di sviluppo (per AutoUpdater)
    static var repoBasePath: String {
        ProcessInfo.processInfo.environment["PERX_REPO_PATH"] ?? "/Users/mpernozzoli/Documents/Attività Peritali/App/PerX BKP16 - fulminazioni Recupero"
    }
    
    // Path installazione sync agent su Windows
    static var syncAgentInstallPath: String {
        ProcessInfo.processInfo.environment["PERX_SYNC_AGENT_PATH"] ?? "C:\\perx_sync_agent"
    }
    
    // MARK: - Worker Ports Configuration
    // Porte standard per tutti i servizi PerX:
    // - Hub:           8080
    // - Email Worker:  5001
    // - WA Bridge:     5002
    // - SyncAgent:     8000 (Windows)
    // - AutoUpdater:   8084
    
    static var emailWorkerURL: String {
        ProcessInfo.processInfo.environment["PERX_EMAIL_WORKER_URL"] ?? "http://localhost:5001"
    }
    
    static var waBridgeURL: String {
        ProcessInfo.processInfo.environment["PERX_WA_BRIDGE_URL"] ?? "http://localhost:5002"
    }
    
    static var syncAgentURL: String {
        ProcessInfo.processInfo.environment["PERX_SYNC_AGENT_URL"] ?? "https://perx-sync-agent.tailca58be.ts.net"
    }
    
    static var autoUpdaterURL: String {
        ProcessInfo.processInfo.environment["PERX_AUTO_UPDATER_URL"] ?? "http://localhost:8084"
    }

    // Supabase server-side configuration.
    static var supabaseURL: String? {
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
    }

    static var supabaseServiceRoleKey: String? {
        ProcessInfo.processInfo.environment["SUPABASE_SERVICE_ROLE_KEY"]
    }
}

// MARK: - Application Startup

let startTime = Date()

print("""
╔═══════════════════════════════════════════════════════════╗
║                      PerX Hub v\(HubConfiguration.version)                      ║
║           Mac Mini - Single Source of Truth               ║
╚═══════════════════════════════════════════════════════════╝
""")

print("[Hub] Starting at \(Date())")
print("[Hub] Base path: \(HubConfiguration.basePath)")
print("[Hub] Vault path: \(HubConfiguration.vaultPath)")
print("[Hub] Hub ID: \(HubConfiguration.hubID)")
print("[Hub] Default tenant: \(HubConfiguration.defaultTenantSlug)")
print("[Hub] Supabase configured: \(HubConfiguration.supabaseURL != nil && HubConfiguration.supabaseServiceRoleKey != nil ? "yes" : "no")")

// Create directories if needed
do {
    let fm = FileManager.default
    try fm.createDirectory(atPath: HubConfiguration.vaultPath, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: HubConfiguration.dataPath, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: HubConfiguration.logsPath, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: "\(HubConfiguration.vaultPath)/tenants/\(HubConfiguration.defaultTenantSlug)/sinistri", withIntermediateDirectories: true)
    print("[Hub] Directories created/verified")
} catch {
    print("[Hub] ERROR creating directories: \(error)")
    exit(1)
}

// Initialize database
do {
    try await DatabaseManager.shared.initialize(path: HubConfiguration.dbPath)
    print("[Hub] Database initialized")
} catch {
    print("[Hub] ERROR initializing database: \(error)")
    exit(1)
}

// Initialize VaultManager
do {
    try await VaultManager.shared.initialize(basePath: HubConfiguration.vaultPath)
    print("[Hub] VaultManager initialized")
} catch {
    print("[Hub] ERROR initializing VaultManager: \(error)")
    exit(1)
}

// Initialize AttachmentManager
do {
    try await AttachmentManager.shared.initialize(basePath: HubConfiguration.basePath)
    print("[Hub] AttachmentManager initialized")
} catch {
    print("[Hub] ERROR initializing AttachmentManager: \(error)")
    exit(1)
}

// Configure Vapor
var env = try Environment.detect()
let app = Application(env)

defer {
    app.shutdown()
}

// Server configuration
app.http.server.configuration.hostname = HubConfiguration.hostname
app.http.server.configuration.port = HubConfiguration.port

// Configure routes
try configureRoutes(app, startTime: startTime)

print("[Hub] Server starting on \(HubConfiguration.hostname):\(HubConfiguration.port)")

// Run
try app.run()
