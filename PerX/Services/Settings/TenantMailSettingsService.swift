import Foundation

struct TenantCATPlannerSettings: Codable, Hashable {
    var routeGenerationHour: Int
    var routeReviewWindowMinutes: Int
    var availabilitySlotMinutes: Int
    var availabilityTolerancePercent: Int
    var maxOutsideZoneKilometers: Int

    static let `default` = TenantCATPlannerSettings(
        routeGenerationHour: 9,
        routeReviewWindowMinutes: 60,
        availabilitySlotMinutes: 120,
        availabilityTolerancePercent: 50,
        maxOutsideZoneKilometers: 50
    )
}

struct TenantCATPOI: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var email: String
    var latitude: Double
    var longitude: Double
    var comune: String
    var provincia: String
    var regione: String
    var assignedMunicipalities: [String]
    var note: String

    static func template(index: Int) -> TenantCATPOI {
        TenantCATPOI(
            id: UUID().uuidString,
            displayName: "CAT \(index)",
            email: "cat\(index)@tenant.it",
            latitude: 44.6471,
            longitude: 10.9252,
            comune: "Modena",
            provincia: "MO",
            regione: "Emilia-Romagna",
            assignedMunicipalities: [],
            note: ""
        )
    }
}

struct TenantCATMunicipality: Codable, Identifiable, Hashable {
    var id: String
    var comune: String
    var provincia: String
    var regione: String
    var latitude: Double
    var longitude: Double
    var assignedCATEmails: [String]
    var priority: Int

    static func template(index: Int) -> TenantCATMunicipality {
        TenantCATMunicipality(
            id: UUID().uuidString,
            comune: "Comune \(index)",
            provincia: "MO",
            regione: "Emilia-Romagna",
            latitude: 44.6471,
            longitude: 10.9252,
            assignedCATEmails: [],
            priority: 1
        )
    }
}

struct TenantCATSettings: Codable, Hashable {
    var enabled: Bool
    var planner: TenantCATPlannerSettings
    var technicians: [TenantCATPOI]
    var municipalities: [TenantCATMunicipality]

    static let `default` = TenantCATSettings(
        enabled: true,
        planner: .default,
        technicians: [
            TenantCATPOI(
                id: "cat-modena",
                displayName: "CAT Modena Nord",
                email: "cat.modena@tenant.it",
                latitude: 44.6471,
                longitude: 10.9252,
                comune: "Modena",
                provincia: "MO",
                regione: "Emilia-Romagna",
                assignedMunicipalities: ["Modena", "Carpi"],
                note: "Presidio principale"
            ),
            TenantCATPOI(
                id: "cat-sassuolo",
                displayName: "CAT Area Ceramiche",
                email: "cat.sassuolo@tenant.it",
                latitude: 44.5432,
                longitude: 10.7841,
                comune: "Sassuolo",
                provincia: "MO",
                regione: "Emilia-Romagna",
                assignedMunicipalities: ["Sassuolo", "Rubiera"],
                note: "Supporto sud-ovest"
            )
        ],
        municipalities: [
            TenantCATMunicipality(
                id: "modena",
                comune: "Modena",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.6471,
                longitude: 10.9252,
                assignedCATEmails: ["cat.modena@tenant.it"],
                priority: 1
            ),
            TenantCATMunicipality(
                id: "carpi",
                comune: "Carpi",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.7824,
                longitude: 10.8777,
                assignedCATEmails: ["cat.modena@tenant.it"],
                priority: 1
            ),
            TenantCATMunicipality(
                id: "sassuolo",
                comune: "Sassuolo",
                provincia: "MO",
                regione: "Emilia-Romagna",
                latitude: 44.5432,
                longitude: 10.7841,
                assignedCATEmails: ["cat.sassuolo@tenant.it"],
                priority: 2
            ),
            TenantCATMunicipality(
                id: "rubiera",
                comune: "Rubiera",
                provincia: "RE",
                regione: "Emilia-Romagna",
                latitude: 44.6511,
                longitude: 10.7812,
                assignedCATEmails: ["cat.sassuolo@tenant.it"],
                priority: 2
            )
        ]
    )
}

struct TenantInspectionProviderSettings: Codable, Hashable {
    var mapProvider: String
    var mapsAPIKey: String
    var routingProvider: String
    var routingAPIKey: String
    var geocodingProvider: String
    var geocodingAPIKey: String
    var messagingProvider: String
    var messagingAPIKey: String

    static let `default` = TenantInspectionProviderSettings(
        mapProvider: "google_maps",
        mapsAPIKey: "",
        routingProvider: "google_routes",
        routingAPIKey: "",
        geocodingProvider: "google_geocoding",
        geocodingAPIKey: "",
        messagingProvider: "twilio",
        messagingAPIKey: ""
    )
}

struct TenantMailSettings: Codable {
    var tenantName: String
    var tenantSlug: String
    var internalDomains: [String]
    var internalEmails: [String]
    var systemEmails: [String]
    var secretariatEmails: [String]
    var claimGaranzie: [String]
    var defaultClaimGaranzia: String
    var catSettings: TenantCATSettings
    var providerSettings: TenantInspectionProviderSettings?

    static let `default` = TenantMailSettings(
        tenantName: "Nuovo Studio",
        tenantSlug: "nuovo-studio",
        internalDomains: ["manivaperizie.it", "studioperizie.it"],
        internalEmails: [],
        systemEmails: ["info@pynkstudio.it"],
        secretariatEmails: [],
        claimGaranzie: ["Fenomeno Elettrico"],
        defaultClaimGaranzia: "Fenomeno Elettrico",
        catSettings: .default,
        providerSettings: nil
    )
}

final class TenantMailSettingsService {
    static let shared = TenantMailSettingsService()

    private let defaults = UserDefaults.standard
    private let storageKey = "tenant.mail.settings"

    private init() {}

    var settings: TenantMailSettings {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode(TenantMailSettings.self, from: data) else {
                return .default
            }
            return normalized(decoded)
        }
        set {
            let value = normalized(newValue)
            guard let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: .tenantSettingsChanged, object: nil)
        }
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
        let normalizedGaranzie = normalizeGaranzie(value.claimGaranzie)
        return TenantMailSettings(
            tenantName: value.tenantName.trimmingCharacters(in: .whitespacesAndNewlines),
            tenantSlug: normalizeSlug(value.tenantSlug),
            internalDomains: normalizeDomains(value.internalDomains),
            internalEmails: normalizeEmails(value.internalEmails),
            systemEmails: normalizeEmails(value.systemEmails),
            secretariatEmails: normalizeEmails(value.secretariatEmails),
            claimGaranzie: normalizedGaranzie,
            defaultClaimGaranzia: normalizeDefaultGaranzia(
                value.defaultClaimGaranzia,
                allowed: normalizedGaranzie
            ),
            catSettings: normalizeCATSettings(value.catSettings),
            providerSettings: value.providerSettings.map(normalizeProviderSettings)
        )
    }

    private func normalizeCATSettings(_ value: TenantCATSettings) -> TenantCATSettings {
        TenantCATSettings(
            enabled: value.enabled,
            planner: TenantCATPlannerSettings(
                routeGenerationHour: min(max(value.planner.routeGenerationHour, 0), 23),
                routeReviewWindowMinutes: max(value.planner.routeReviewWindowMinutes, 15),
                availabilitySlotMinutes: max(value.planner.availabilitySlotMinutes, 30),
                availabilityTolerancePercent: min(max(value.planner.availabilityTolerancePercent, 0), 100),
                maxOutsideZoneKilometers: max(value.planner.maxOutsideZoneKilometers, 0)
            ),
            technicians: value.technicians.map(normalizeCATPOI),
            municipalities: value.municipalities.map(normalizeCATMunicipality)
        )
    }

    private func normalizeCATPOI(_ value: TenantCATPOI) -> TenantCATPOI {
        TenantCATPOI(
            id: value.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : value.id,
            displayName: value.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: normalizeEmail(value.email),
            latitude: value.latitude,
            longitude: value.longitude,
            comune: value.comune.trimmingCharacters(in: .whitespacesAndNewlines),
            provincia: value.provincia.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            regione: value.regione.trimmingCharacters(in: .whitespacesAndNewlines),
            assignedMunicipalities: Array(Set(value.assignedMunicipalities
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })).sorted(),
            note: value.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func normalizeCATMunicipality(_ value: TenantCATMunicipality) -> TenantCATMunicipality {
        TenantCATMunicipality(
            id: value.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : value.id,
            comune: value.comune.trimmingCharacters(in: .whitespacesAndNewlines),
            provincia: value.provincia.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            regione: value.regione.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: value.latitude,
            longitude: value.longitude,
            assignedCATEmails: normalizeEmails(value.assignedCATEmails),
            priority: min(max(value.priority, 1), 3)
        )
    }

    private func normalizeProviderSettings(_ value: TenantInspectionProviderSettings) -> TenantInspectionProviderSettings {
        TenantInspectionProviderSettings(
            mapProvider: value.mapProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            mapsAPIKey: value.mapsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            routingProvider: value.routingProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            routingAPIKey: value.routingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            geocodingProvider: value.geocodingProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            geocodingAPIKey: value.geocodingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            messagingProvider: value.messagingProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            messagingAPIKey: value.messagingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func normalizeGaranzie(_ values: [String]) -> [String] {
        var normalized = Array(Set(values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted()
        if !normalized.contains("Fenomeno Elettrico") {
            normalized.insert("Fenomeno Elettrico", at: 0)
        }
        return normalized
    }

    private func normalizeDefaultGaranzia(_ value: String, allowed: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowed.contains(trimmed) ? trimmed : "Fenomeno Elettrico"
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

extension Notification.Name {
    static let tenantSettingsChanged = Notification.Name("tenantSettingsChanged")
}
