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

struct TenantVideoInspectionSettings: Codable, Hashable {
    var enabled: Bool
    var assignmentRunHour: Int
    var firstSlotHour: Int
    var slotMinutes: Int

    static let `default` = TenantVideoInspectionSettings(
        enabled: true,
        assignmentRunHour: 9,
        firstSlotHour: 10,
        slotMinutes: 30
    )
}

struct TenantInspectionProviderSettings: Codable, Hashable {
    var mapProvider: String
    var mapsAPIKey: String
    var routingProvider: String
    var routingAPIKey: String
    var routingEnabled: Bool
    var routingCacheTTLDays: Int
    var geocodingProvider: String
    var geocodingAPIKey: String
    var messagingProvider: String
    var messagingAPIKey: String

    init(
        mapProvider: String,
        mapsAPIKey: String,
        routingProvider: String,
        routingAPIKey: String,
        routingEnabled: Bool = false,
        routingCacheTTLDays: Int = 14,
        geocodingProvider: String,
        geocodingAPIKey: String,
        messagingProvider: String,
        messagingAPIKey: String
    ) {
        self.mapProvider = mapProvider
        self.mapsAPIKey = mapsAPIKey
        self.routingProvider = routingProvider
        self.routingAPIKey = routingAPIKey
        self.routingEnabled = routingEnabled
        self.routingCacheTTLDays = routingCacheTTLDays
        self.geocodingProvider = geocodingProvider
        self.geocodingAPIKey = geocodingAPIKey
        self.messagingProvider = messagingProvider
        self.messagingAPIKey = messagingAPIKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mapProvider = try container.decode(String.self, forKey: .mapProvider)
        mapsAPIKey = try container.decode(String.self, forKey: .mapsAPIKey)
        routingProvider = try container.decode(String.self, forKey: .routingProvider)
        routingAPIKey = try container.decode(String.self, forKey: .routingAPIKey)
        routingEnabled = try container.decodeIfPresent(Bool.self, forKey: .routingEnabled) ?? false
        routingCacheTTLDays = try container.decodeIfPresent(Int.self, forKey: .routingCacheTTLDays) ?? 14
        geocodingProvider = try container.decode(String.self, forKey: .geocodingProvider)
        geocodingAPIKey = try container.decode(String.self, forKey: .geocodingAPIKey)
        messagingProvider = try container.decode(String.self, forKey: .messagingProvider)
        messagingAPIKey = try container.decode(String.self, forKey: .messagingAPIKey)
    }

    static let `default` = TenantInspectionProviderSettings(
        mapProvider: "google_maps",
        mapsAPIKey: "",
        routingProvider: "google_routes",
        routingAPIKey: "",
        routingEnabled: false,
        routingCacheTTLDays: 14,
        geocodingProvider: "google_geocoding",
        geocodingAPIKey: "",
        messagingProvider: "twilio",
        messagingAPIKey: ""
    )
}

struct TenantBrandingSettings: Codable, Equatable {
    var iconDataURL: String?
    var badgeDataURL: String?
    var logoDataURL: String?
    var primaryColor: String?

    static let empty = TenantBrandingSettings(
        iconDataURL: nil,
        badgeDataURL: nil,
        logoDataURL: nil,
        primaryColor: nil
    )
}

struct TenantMailSettings: Codable {
    var tenantName: String
    var tenantSlug: String
    var portalDomains: [String]
    var internalDomains: [String]
    var internalEmails: [String]
    var systemEmails: [String]
    var secretariatEmails: [String]
    var claimGaranzie: [String]
    var defaultClaimGaranzia: String
    var catSettings: TenantCATSettings
    var videoInspectionSettings: TenantVideoInspectionSettings
    var providerSettings: TenantInspectionProviderSettings?
    var branding: TenantBrandingSettings?

    init(
        tenantName: String,
        tenantSlug: String,
        portalDomains: [String] = [],
        internalDomains: [String],
        internalEmails: [String],
        systemEmails: [String],
        secretariatEmails: [String],
        claimGaranzie: [String],
        defaultClaimGaranzia: String,
        catSettings: TenantCATSettings,
        videoInspectionSettings: TenantVideoInspectionSettings,
        providerSettings: TenantInspectionProviderSettings?,
        branding: TenantBrandingSettings?
    ) {
        self.tenantName = tenantName
        self.tenantSlug = tenantSlug
        self.portalDomains = portalDomains
        self.internalDomains = internalDomains
        self.internalEmails = internalEmails
        self.systemEmails = systemEmails
        self.secretariatEmails = secretariatEmails
        self.claimGaranzie = claimGaranzie
        self.defaultClaimGaranzia = defaultClaimGaranzia
        self.catSettings = catSettings
        self.videoInspectionSettings = videoInspectionSettings
        self.providerSettings = providerSettings
        self.branding = branding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tenantName = try container.decode(String.self, forKey: .tenantName)
        tenantSlug = try container.decode(String.self, forKey: .tenantSlug)
        portalDomains = try container.decodeIfPresent([String].self, forKey: .portalDomains) ?? []
        internalDomains = try container.decode([String].self, forKey: .internalDomains)
        internalEmails = try container.decode([String].self, forKey: .internalEmails)
        systemEmails = try container.decode([String].self, forKey: .systemEmails)
        secretariatEmails = try container.decode([String].self, forKey: .secretariatEmails)
        claimGaranzie = try container.decode([String].self, forKey: .claimGaranzie)
        defaultClaimGaranzia = try container.decode(String.self, forKey: .defaultClaimGaranzia)
        catSettings = try container.decode(TenantCATSettings.self, forKey: .catSettings)
        videoInspectionSettings = try container.decodeIfPresent(TenantVideoInspectionSettings.self, forKey: .videoInspectionSettings) ?? .default
        providerSettings = try container.decodeIfPresent(TenantInspectionProviderSettings.self, forKey: .providerSettings)
        branding = try container.decodeIfPresent(TenantBrandingSettings.self, forKey: .branding)
    }

    static let `default` = TenantMailSettings(
        tenantName: "Nuovo Studio",
        tenantSlug: "nuovo-studio",
        portalDomains: [],
        internalDomains: ["manivaperizie.it", "studioperizie.it"],
        internalEmails: [],
        systemEmails: ["info@pynkstudio.it"],
        secretariatEmails: [],
        claimGaranzie: ["Fenomeno Elettrico"],
        defaultClaimGaranzia: "Fenomeno Elettrico",
        catSettings: .default,
        videoInspectionSettings: .default,
        providerSettings: nil,
        branding: nil
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
            var cachedValue = value
            // Le chiavi provider restano server-side e non vengono persistite sul client.
            cachedValue.providerSettings = nil
            guard let data = try? JSONEncoder().encode(cachedValue) else { return }
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
            portalDomains: normalizeDomains(value.portalDomains),
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
            videoInspectionSettings: normalizeVideoInspectionSettings(value.videoInspectionSettings),
            providerSettings: value.providerSettings.map(normalizeProviderSettings),
            branding: value.branding
        )
    }

    private func normalizeVideoInspectionSettings(_ value: TenantVideoInspectionSettings) -> TenantVideoInspectionSettings {
        TenantVideoInspectionSettings(
            enabled: value.enabled,
            assignmentRunHour: min(max(value.assignmentRunHour, 0), 23),
            firstSlotHour: min(max(value.firstSlotHour, 0), 23),
            slotMinutes: min(max(value.slotMinutes, 15), 60)
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
            routingEnabled: value.routingEnabled,
            routingCacheTTLDays: max(value.routingCacheTTLDays, 1),
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
