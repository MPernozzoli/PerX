"""
Schemas for CAT inspection workflow automation.
"""
from __future__ import annotations

from datetime import date, datetime, time
from typing import Optional

from pydantic import BaseModel, Field


class InspectionPreferredSlotInput(BaseModel):
    date: date
    start_time: time
    end_time: time
    label: Optional[str] = None


class InspectionSchedulingPreferencesUpsert(BaseModel):
    address_line: Optional[str] = None
    municipality: Optional[str] = None
    province: Optional[str] = None
    region: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    confirmed_at: Optional[datetime] = None
    preferred_slots: list[InspectionPreferredSlotInput] = Field(default_factory=list)
    requested_duration_minutes: Optional[int] = Field(default=None, ge=15, le=60)
    notes: Optional[str] = None


class InspectionSchedulingPreferencesResponse(BaseModel):
    claim_id: str
    state: str
    workflow_stage: Optional[str] = None
    eligible_route_generation_date: Optional[date] = None
    preferred_slots_count: int = 0
    address_confirmed: bool = False


class InspectionManualAppointmentCreate(BaseModel):
    scheduled_start: datetime
    scheduled_end: datetime
    cat_user_id: Optional[str] = None
    cat_email: Optional[str] = None
    note: Optional[str] = None


class InspectionRouteRunRequest(BaseModel):
    tenant_id: Optional[str] = None
    plan_date: Optional[date] = None
    force: bool = False


class InspectionRouteDecisionRequest(BaseModel):
    reason_code: str = "other"
    reason: Optional[str] = None


class InspectionAvailabilityWindowInput(BaseModel):
    start_time: time
    end_time: time


class InspectionAvailabilityOverrideUpsert(BaseModel):
    is_available: bool = True
    note: Optional[str] = None
    windows: list[InspectionAvailabilityWindowInput] = Field(default_factory=list)


class InspectionAvailabilityCommitmentResponse(BaseModel):
    id: str
    tenant_name: Optional[str] = None
    label: str
    start_time: time
    end_time: time


class InspectionAvailabilityDayResponse(BaseModel):
    date: date
    is_available: bool = False
    note: Optional[str] = None
    windows: list[InspectionAvailabilityWindowInput] = Field(default_factory=list)
    external_commitments: list[InspectionAvailabilityCommitmentResponse] = Field(default_factory=list)
    has_confirmed_route: bool = False
    source: str = "default"


class InspectionAvailabilityMonthResponse(BaseModel):
    owner_user_id: str
    month: date
    items: list[InspectionAvailabilityDayResponse] = Field(default_factory=list)


class InspectionRoutePreferredWindowResponse(BaseModel):
    start_time: time
    end_time: time
    label: Optional[str] = None


class InspectionRouteStopResponse(BaseModel):
    claim_id: str
    claim_reference: Optional[str] = None
    starts_at: datetime
    ends_at: datetime
    municipality: Optional[str] = None
    province: Optional[str] = None
    region: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    masked_location: Optional[str] = None
    outside_zone: bool = False
    distance_from_previous_km: float = 0
    duration_minutes: int = 0
    asset_count: int = 0
    complexity: Optional[str] = None
    manually_fixed: bool = False
    note: Optional[str] = None
    preferred_windows: list[InspectionRoutePreferredWindowResponse] = Field(default_factory=list)


class InspectionRouteProposalResponse(BaseModel):
    event_id: str
    tenant_id: str
    owner_user_id: str
    owner_email: Optional[str] = None
    owner_name: Optional[str] = None
    title: str
    plan_date: date
    generated_at: Optional[datetime] = None
    starts_at: datetime
    ends_at: datetime
    review_deadline: Optional[datetime] = None
    status: str
    total_distance_km: float = 0
    total_duration_minutes: int = 0
    tenant_names: list[str] = Field(default_factory=list)
    stops: list[InspectionRouteStopResponse] = Field(default_factory=list)
    rejection_reason_code: Optional[str] = None
    rejection_reason: Optional[str] = None


class InspectionRouteProposalListResponse(BaseModel):
    items: list[InspectionRouteProposalResponse]
    total: int


class InspectionRouteRunResponse(BaseModel):
    tenant_id: str
    plan_date: date
    processed_at: datetime
    generated_routes_count: int = 0
    claims_planned: int = 0
    claims_fallback_manual: int = 0
    skipped_claims: int = 0
    route_event_ids: list[str] = Field(default_factory=list)
    fallback_claim_ids: list[str] = Field(default_factory=list)


class InspectionExpirationProcessResponse(BaseModel):
    processed_at: datetime
    expired_routes_count: int = 0
    replanned_routes_count: int = 0
    manual_fallback_claims: int = 0
