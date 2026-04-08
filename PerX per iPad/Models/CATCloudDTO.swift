//
//  CATCloudDTO.swift
//  PerX per iPad
//
//  DTO backend per il flusso CAT.
//

import Foundation

struct CloudTenantSettingsDTO: Decodable {
    let tenant_name: String
    let tenant_slug: String
    let cat_settings: CloudTenantCATSettingsDTO
}

struct CloudTenantCATSettingsDTO: Decodable {
    let enabled: Bool
    let planner: CloudTenantCATPlannerDTO
    let technicians: [CloudTenantCATTechnicianDTO]
    let municipalities: [CloudTenantCATMunicipalityDTO]
}

struct CloudTenantCATPlannerDTO: Decodable {
    let route_generation_hour: Int
    let route_review_window_minutes: Int
    let availability_slot_minutes: Int
    let availability_tolerance_percent: Int
    let max_outside_zone_kilometers: Int
}

struct CloudTenantCATTechnicianDTO: Decodable {
    let id: String
    let display_name: String
    let email: String
    let latitude: Double
    let longitude: Double
    let comune: String
    let provincia: String
    let regione: String
    let assigned_municipalities: [String]
    let note: String
}

struct CloudTenantCATMunicipalityDTO: Decodable {
    let id: String
    let comune: String
    let provincia: String
    let regione: String
    let latitude: Double
    let longitude: Double
    let assigned_cat_emails: [String]
    let priority: Int
}

struct CloudInspectionAvailabilityWindowDTO: Codable, Hashable {
    let start_time: String
    let end_time: String
}

struct CloudInspectionAvailabilityOverrideRequestDTO: Encodable {
    let is_available: Bool
    let note: String?
    let windows: [CloudInspectionAvailabilityWindowDTO]
}

struct CloudInspectionAvailabilityCommitmentDTO: Decodable, Hashable {
    let id: String
    let tenant_name: String?
    let label: String
    let start_time: String
    let end_time: String
}

struct CloudInspectionAvailabilityDayDTO: Decodable, Hashable {
    let date: String
    let is_available: Bool
    let note: String?
    let windows: [CloudInspectionAvailabilityWindowDTO]
    let external_commitments: [CloudInspectionAvailabilityCommitmentDTO]
    let has_confirmed_route: Bool
    let source: String
}

struct CloudInspectionAvailabilityMonthDTO: Decodable {
    let owner_user_id: String
    let month: String
    let items: [CloudInspectionAvailabilityDayDTO]
}

struct CloudInspectionRouteDecisionRequestDTO: Encodable {
    let reason_code: String
    let reason: String?
}

struct CloudInspectionRoutePreferredWindowDTO: Decodable, Hashable {
    let start_time: String
    let end_time: String
    let label: String?
}

struct CloudInspectionRouteStopDTO: Decodable, Hashable {
    let claim_id: String
    let claim_reference: String?
    let starts_at: Date
    let ends_at: Date
    let municipality: String?
    let province: String?
    let region: String?
    let latitude: Double?
    let longitude: Double?
    let masked_location: String?
    let outside_zone: Bool
    let distance_from_previous_km: Double
    let duration_minutes: Int
    let asset_count: Int
    let complexity: String?
    let manually_fixed: Bool
    let note: String?
    let preferred_windows: [CloudInspectionRoutePreferredWindowDTO]
}

struct CloudInspectionRouteDTO: Decodable, Hashable {
    let event_id: String
    let tenant_id: String
    let owner_user_id: String
    let owner_email: String?
    let owner_name: String?
    let title: String
    let plan_date: String
    let generated_at: Date?
    let starts_at: Date
    let ends_at: Date
    let review_deadline: Date?
    let status: String
    let total_distance_km: Double
    let total_duration_minutes: Int
    let tenant_names: [String]
    let stops: [CloudInspectionRouteStopDTO]
    let rejection_reason_code: String?
    let rejection_reason: String?
}

struct CloudInspectionRouteListResponseDTO: Decodable {
    let items: [CloudInspectionRouteDTO]
    let total: Int
}

struct CloudInspectionRouteRunResponseDTO: Decodable {
    let tenant_id: String
    let plan_date: String
    let processed_at: Date
    let generated_routes_count: Int
    let claims_planned: Int
    let claims_fallback_manual: Int
    let skipped_claims: Int
    let route_event_ids: [String]
    let fallback_claim_ids: [String]
}

struct CloudInspectionExpirationProcessResponseDTO: Decodable {
    let processed_at: Date
    let expired_routes_count: Int
    let replanned_routes_count: Int
    let manual_fallback_claims: Int
}
