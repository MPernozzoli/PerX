import Foundation

/// Segreti opzionali scritti da Hub Monitor in `data/monitor-secrets.json` (priorità sulle env del plist).
struct HubRuntimeSecretsFile: Codable {
    var supabaseURL: String?
    var supabaseServiceRoleKey: String?
    var storageSharedSecret: String?
}

extension HubConfiguration {
    private static var runtimeSecrets: HubRuntimeSecretsFile?

    static func loadRuntimeSecretsFromDisk() {
        let path = "\(dataPath)/monitor-secrets.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else {
            runtimeSecrets = nil
            return
        }
        runtimeSecrets = try? JSONDecoder().decode(HubRuntimeSecretsFile.self, from: data)
    }

    private static func trimmedOptional(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// URL progetto Supabase: file `monitor-secrets.json` se valorizzato, altrimenti env.
    static var supabaseURL: String? {
        if let f = trimmedOptional(runtimeSecrets?.supabaseURL) { return f }
        return trimmedOptional(ProcessInfo.processInfo.environment["SUPABASE_URL"])
    }

    /// Chiave segreta server Supabase: stessa priorità.
    static var supabaseServiceRoleKey: String? {
        if let f = trimmedOptional(runtimeSecrets?.supabaseServiceRoleKey) { return f }
        return trimmedOptional(ProcessInfo.processInfo.environment["SUPABASE_SERVICE_ROLE_KEY"])
    }

    /// Token condiviso storage interno: stessa priorità.
    static var storageSharedSecret: String {
        if let f = trimmedOptional(runtimeSecrets?.storageSharedSecret) { return f }
        return ProcessInfo.processInfo.environment["PERX_STORAGE_SHARED_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
