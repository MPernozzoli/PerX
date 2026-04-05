//
//  CATDomain.swift
//  PerX per iPad
//
//  Dominio mock e infrastruttura base per il flusso CAT.
//

import Foundation
import CoreLocation

enum iPadUserExperience {
    case standard
    case cat
}

extension CloudProfileDTO {
    var normalizedRoles: [String] {
        roles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    var isCATUser: Bool {
        normalizedRoles.contains("cat")
    }
}

extension SessionCoordinator {
    var currentExperience: iPadUserExperience {
        currentCloudProfile?.isCATUser == true ? .cat : .standard
    }

    var isCATUser: Bool {
        currentExperience == .cat
    }
}

struct CATSchedulingRules: Codable {
    let routeGenerationHour: Int
    let routeReviewWindowMinutes: Int
    let availabilitySlotMinutes: Int
    let availabilityTolerancePercent: Double
    let maxOutsideZoneKilometers: Double

    static let `default` = CATSchedulingRules(
        routeGenerationHour: 9,
        routeReviewWindowMinutes: 60,
        availabilitySlotMinutes: 120,
        availabilityTolerancePercent: 0.5,
        maxOutsideZoneKilometers: 50
    )
}

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
        "\(Self.timeString(hour: startHour, minute: startMinute))-\(Self.timeString(hour: endHour, minute: endMinute))"
    }

    var expandedLabel: String {
        let baseMinutes = max(durationMinutes, CATSchedulingRules.default.availabilitySlotMinutes)
        let toleranceMinutes = Int(Double(baseMinutes) * CATSchedulingRules.default.availabilityTolerancePercent)
        let lower = offset(minutes: -toleranceMinutes)
        let upper = offsetFromEnd(minutes: toleranceMinutes)
        return "\(label) • margine \(lower)-\(upper)"
    }

    var durationMinutes: Int {
        ((endHour * 60) + endMinute) - ((startHour * 60) + startMinute)
    }

    func offset(minutes: Int) -> String {
        Self.timeString(totalMinutes: (startHour * 60) + startMinute + minutes)
    }

    func offsetFromEnd(minutes: Int) -> String {
        Self.timeString(totalMinutes: (endHour * 60) + endMinute + minutes)
    }

    private static func timeString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private static func timeString(totalMinutes: Int) -> String {
        let normalized = max(totalMinutes, 0)
        let hour = normalized / 60
        let minute = normalized % 60
        return timeString(hour: hour, minute: minute)
    }
}

struct CATExternalCommitment: Codable, Identifiable, Hashable {
    let id: String
    let tenantName: String
    let label: String
    let window: CATTimeWindow
}

struct CATAvailabilityDay: Codable, Identifiable, Hashable {
    let id: String
    let date: Date
    var isAvailable: Bool
    var windows: [CATTimeWindow]
    var note: String
    var externalCommitments: [CATExternalCommitment]
    var hasConfirmedRoute: Bool

    init(
        date: Date,
        isAvailable: Bool,
        windows: [CATTimeWindow],
        note: String = "",
        externalCommitments: [CATExternalCommitment] = [],
        hasConfirmedRoute: Bool = false
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.id = Self.identifier(for: date)
        self.isAvailable = isAvailable
        self.windows = windows.sorted {
            ($0.startHour, $0.startMinute, $0.endHour, $0.endMinute) <
            ($1.startHour, $1.startMinute, $1.endHour, $1.endMinute)
        }
        self.note = note
        self.externalCommitments = externalCommitments
        self.hasConfirmedRoute = hasConfirmedRoute
    }

    static func identifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }
}

enum CATRoutePlanStatus: String, Codable, CaseIterable, Identifiable {
    case pendingApproval
    case confirmed
    case needsRecalculation
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pendingApproval: return "Da approvare"
        case .confirmed: return "Confermato"
        case .needsRecalculation: return "Da ricalcolare"
        case .rejected: return "Rifiutato"
        }
    }
}

enum CATRouteRejectionReason: String, Codable, CaseIterable, Identifiable {
    case tooLong
    case outsideZone
    case unavailable
    case impossible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooLong: return "Percorso troppo lungo"
        case .outsideZone: return "Fuori zona"
        case .unavailable: return "Non disponibile"
        case .impossible: return "Impossibilitato"
        }
    }
}

enum CATClaimComplexity: String, Codable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "Bassa"
        case .medium: return "Media"
        case .high: return "Alta"
        }
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
}

struct CATRouteStop: Codable, Identifiable, Hashable {
    let id: String
    let claimReference: String
    let municipality: String
    let province: String
    let region: String
    let latitude: Double
    let longitude: Double
    let plannedWindow: CATTimeWindow
    let preferredWindows: [CATTimeWindow]
    let durationMinutes: Int
    let assetCount: Int
    let complexity: CATClaimComplexity
    let outsideZone: Bool
    let manuallyFixed: Bool
    let redactedLocation: String
    let workflow: [CATWorkflowStep]
    let note: String

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

struct CATMunicipalityCoverage: Codable, Identifiable, Hashable {
    let id: String
    let comune: String
    let provincia: String
    let regione: String
    let latitude: Double
    let longitude: Double
    let priority: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CATTechnicianPOI: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let tenantNames: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CATTenantTerritorySnapshot: Codable {
    let poi: CATTechnicianPOI
    let municipalities: [CATMunicipalityCoverage]
    let provinces: [String]
    let regions: [String]
}

struct CATDashboardSnapshot {
    let pendingApprovals: Int
    let confirmedRoutes: Int
    let appointmentsToday: Int
    let assignedMunicipalities: Int
    let outsideZoneStops: Int
    let nextPendingRoute: CATRoutePlan?
    let nextConfirmedRoute: CATRoutePlan?
}

extension CATWorkflowStep {
    static let defaultInspectionFlow: [CATWorkflowStep] = [
        CATWorkflowStep(
            id: "checkin",
            title: "Check-in sopralluogo",
            detail: "Conferma arrivo in zona e apertura scheda operativa.",
            isRequired: true
        ),
        CATWorkflowStep(
            id: "context",
            title: "Verifica contesto",
            detail: "Raccogli dati di scenario, accessibilità e presenza danno.",
            isRequired: true
        ),
        CATWorkflowStep(
            id: "assets",
            title: "Censimento beni",
            detail: "Stima quantità beni e complessità prima del rilievo completo.",
            isRequired: true
        ),
        CATWorkflowStep(
            id: "media",
            title: "Acquisizione media",
            detail: "Foto/video guidati e note vocali a supporto.",
            isRequired: true
        ),
        CATWorkflowStep(
            id: "closure",
            title: "Chiusura visita",
            detail: "Esito, anomalie, tempi e consegna al flusso peritale.",
            isRequired: true
        )
    ]
}
