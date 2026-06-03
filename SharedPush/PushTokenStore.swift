import Foundation

/// Local cache of registered APNs / VoIP tokens so we can unregister them
/// from the backend on logout. Per-app key so multiple PerX apps on the
/// same device don't clobber each other.
public final class PushTokenStore {
    private let apnsKey: String
    private let voipKey: String

    public init(appIdentifier: String) {
        self.apnsKey = "perx_push_apns_\(appIdentifier)"
        self.voipKey = "perx_push_voip_\(appIdentifier)"
    }

    public func savedToken(type: String) -> String? {
        UserDefaults.standard.string(forKey: key(for: type))
    }

    public func save(_ token: String, type: String) {
        UserDefaults.standard.set(token, forKey: key(for: type))
    }

    public func clearAll() {
        UserDefaults.standard.removeObject(forKey: apnsKey)
        UserDefaults.standard.removeObject(forKey: voipKey)
    }

    public func allTokens() -> [String] {
        [savedToken(type: "apns"), savedToken(type: "voip")].compactMap { $0 }
    }

    private func key(for type: String) -> String {
        type == "voip" ? voipKey : apnsKey
    }
}
