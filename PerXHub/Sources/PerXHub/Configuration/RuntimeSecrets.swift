import Foundation

/// Segreti opzionali scritti da Hub Monitor in `data/monitor-secrets.json` (priorità sulle env del plist).
struct HubRuntimeSecretsFile: Codable {
    var supabaseURL: String?
    var supabaseServiceRoleKey: String?
    var storageSharedSecret: String?
    /// Token per le route Hub chiamate da LAN/VPN/tunnel (vedi `HubAccessMiddleware`).
    var hubAPIToken: String?
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

    /// Segreto valorizzato davvero: scarta vuoti e placeholder dei template versionati
    /// (`REPLACE_WITH_...`, `replace-with-...`), che sono pubblici e non vanno mai accettati.
    private static func realSecret(_ s: String?) -> String? {
        guard let value = trimmedOptional(s) else { return nil }
        let lowered = value.lowercased()
        return lowered.hasPrefix("replace_with") || lowered.hasPrefix("replace-with") ? nil : value
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

    /// Token condiviso storage interno: stessa priorità. Vuoto = storage remoto disabilitato.
    static var storageSharedSecret: String {
        if let f = realSecret(runtimeSecrets?.storageSharedSecret) { return f }
        return realSecret(ProcessInfo.processInfo.environment["PERX_STORAGE_SHARED_SECRET"]) ?? ""
    }

    /// Token per l'accesso non locale alle route Hub: stessa priorità. `nil` = solo loopback.
    static var hubAPIToken: String? {
        if let f = realSecret(runtimeSecrets?.hubAPIToken) { return f }
        return realSecret(ProcessInfo.processInfo.environment["PERX_HUB_API_TOKEN"])
    }

    /// Token che il WA Bridge invia in `X-PerX-WA-Bridge-Token` (stessa env del bridge).
    static var waBridgeInternalToken: String? {
        realSecret(ProcessInfo.processInfo.environment["WA_BRIDGE_INTERNAL_TOKEN"])
    }
}
