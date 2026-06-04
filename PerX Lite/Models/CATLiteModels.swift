import Foundation
import CoreLocation

// MARK: - Navigation app preference

enum NavigationApp: String, CaseIterable {
    case apple = "apple"
    case google = "google"

    var displayName: String {
        switch self {
        case .apple: return "Mappe Apple"
        case .google: return "Google Maps"
        }
    }
}

// MARK: - Status / reason enums

enum CATRoutePlanStatus: String, Codable, CaseIterable, Identifiable {
    case pendingApproval
    case confirmed
    case needsRecalculation
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pendingApproval:     return "Da approvare"
        case .confirmed:           return "Confermato"
        case .needsRecalculation:  return "Da ricalcolare"
        case .rejected:            return "Rifiutato"
        }
    }

    init(cloudStatus: String) {
        switch cloudStatus.lowercased() {
        case "accepted":             self = .confirmed
        case "rejected":             self = .rejected
        case "expired", "superseded": self = .needsRecalculation
        default:                     self = .pendingApproval
        }
    }
}

enum CATRouteRejectionReason: String, Codable, CaseIterable, Identifiable {
    case tooLong, outsideZone, unavailable, impossible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooLong:     return "Percorso troppo lungo"
        case .outsideZone: return "Fuori zona"
        case .unavailable: return "Non disponibile"
        case .impossible:  return "Impossibilitato"
        }
    }

    var backendCode: String {
        switch self {
        case .tooLong:     return "route_too_long"
        case .outsideZone: return "outside_zone"
        case .unavailable: return "unavailable"
        case .impossible:  return "impossible"
        }
    }

    init?(backendCode: String?) {
        switch backendCode?.lowercased() {
        case "route_too_long":              self = .tooLong
        case "outside_zone":               self = .outsideZone
        case "unavailable", "review_window_expired": self = .unavailable
        case "impossible":                 self = .impossible
        default: return nil
        }
    }
}

enum CATClaimComplexity: String, Codable {
    case low, medium, high

    var title: String {
        switch self {
        case .low:    return "Bassa"
        case .medium: return "Media"
        case .high:   return "Alta"
        }
    }
}

// MARK: - Domain structs

struct CATTimeWindow: Codable, Identifiable, Hashable {
    var id: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    init(
        id: String = UUID().uuidString,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0
    ) {
        self.id = id
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    var label: String {
        "\(Self.fmt(startHour, startMinute))–\(Self.fmt(endHour, endMinute))"
    }

    private static func fmt(_ h: Int, _ m: Int) -> String {
        String(format: "%02d:%02d", h, m)
    }
}

struct CATRouteConstraintSummary: Codable, Hashable {
    let fixedManualStops: Int
    let outsideZoneStops: Int
    let respectedWindowsPercent: Int
    let crossTenantCommitments: Int
}

struct CATWorkflowStep: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let isRequired: Bool

    static let defaultInspectionFlow: [CATWorkflowStep] = [
        CATWorkflowStep(id: "checkin", title: "Check-in sopralluogo",
                        detail: "Conferma arrivo in zona e apertura scheda operativa.", isRequired: true),
        CATWorkflowStep(id: "context", title: "Verifica contesto",
                        detail: "Raccogli dati di scenario, accessibilità e presenza danno.", isRequired: true),
        CATWorkflowStep(id: "assets", title: "Censimento beni",
                        detail: "Stima quantità beni e complessità prima del rilievo completo.", isRequired: true),
        CATWorkflowStep(id: "media", title: "Acquisizione media",
                        detail: "Foto/video guidati e note vocali a supporto.", isRequired: true),
        CATWorkflowStep(id: "closure", title: "Chiusura visita",
                        detail: "Esito, anomalie, tempi e consegna al flusso peritale.", isRequired: true),
    ]
}

struct CATRouteStop: Codable, Identifiable, Hashable {
    let id: String
    let claimReference: String
    let municipality: String
    let province: String
    let latitude: Double
    let longitude: Double
    let plannedWindow: CATTimeWindow
    let durationMinutes: Int
    let assetCount: Int
    let complexity: CATClaimComplexity
    let outsideZone: Bool
    let manuallyFixed: Bool
    let redactedLocation: String
    let note: String
    let workflow: [CATWorkflowStep]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CATRoutePlan: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let tenantNames: [String]
    let generatedAt: Date
    let reviewDeadline: Date
    let routeDate: Date
    var status: CATRoutePlanStatus
    var rejectionReason: CATRouteRejectionReason?
    let totalKilometers: Double
    let driveMinutes: Int
    let visitMinutes: Int
    let coverageSummary: String
    let constraints: CATRouteConstraintSummary
    let stops: [CATRouteStop]

    var totalAppointments: Int { stops.count }
}
