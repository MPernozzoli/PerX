import Foundation

struct TenantMailSettings: Codable {
    var tenantName: String
    var tenantSlug: String
    var internalDomains: [String]
    var internalEmails: [String]
    var systemEmails: [String]
    var secretariatEmails: [String]

    static let `default` = TenantMailSettings(
        tenantName: "Nuovo Studio",
        tenantSlug: "nuovo-studio",
        internalDomains: ["manivaperizie.it", "studioperizie.it"],
        internalEmails: [],
        systemEmails: ["info@pynkstudio.it"],
        secretariatEmails: []
    )
}

final class TenantMailSettingsProvider {
    static let shared = TenantMailSettingsProvider()

    private let defaults = UserDefaults.standard
    private let storageKey = "tenant.mail.settings"

    private init() {}

    var settings: TenantMailSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TenantMailSettings.self, from: data) else {
            return .default
        }
        return normalized(decoded)
    }

    func isInternalEmail(_ email: String) -> Bool {
        let normalizedEmail = normalizeEmail(email)
        if normalizedEmail.isEmpty { return false }

        let config = settings
        let configuredEmails = Set(config.internalEmails + config.systemEmails + config.secretariatEmails)
        if configuredEmails.contains(normalizedEmail) {
            return true
        }

        let domain = normalizedEmail.components(separatedBy: "@").last ?? ""
        return config.internalDomains.contains(domain)
    }

    func allInternalDomains() -> [String] {
        settings.internalDomains
    }

    private func normalized(_ value: TenantMailSettings) -> TenantMailSettings {
        TenantMailSettings(
            tenantName: value.tenantName.trimmingCharacters(in: .whitespacesAndNewlines),
            tenantSlug: normalizeSlug(value.tenantSlug),
            internalDomains: normalizeDomains(value.internalDomains),
            internalEmails: normalizeEmails(value.internalEmails),
            systemEmails: normalizeEmails(value.systemEmails),
            secretariatEmails: normalizeEmails(value.secretariatEmails)
        )
    }

    private func normalizeDomains(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })).sorted()
    }

    private func normalizeEmails(_ values: [String]) -> [String] {
        Array(Set(values.map(normalizeEmail).filter { !$0.isEmpty })).sorted()
    }

    private func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeSlug(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            if character == "-" || character == "_" { return character }
            return "-"
        }
        return String(allowed)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
