"""
Dedicated inspection workflow models.
"""
from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    Numeric,
    String,
    Time,
)
from sqlalchemy.sql import func

from app.core.database import Base


class InspectionPreference(Base):
    __tablename__ = "inspection_preferences"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    address_line = Column(String, nullable=True)
    municipality = Column(String, nullable=True)
    province = Column(String, nullable=True)
    region = Column(String, nullable=True)
    latitude = Column(Numeric(10, 6), nullable=True)
    longitude = Column(Numeric(10, 6), nullable=True)
    confirmed_at = Column(DateTime(timezone=True), nullable=True)
    requested_duration_minutes = Column(Integer, nullable=True)
    notes = Column(String, nullable=True)
    source = Column(String, nullable=False, default="portal")
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("uq_inspection_preferences_claim", "claim_id", unique=True),
    )


class InspectionPreferenceSlot(Base):
    __tablename__ = "inspection_preference_slots"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    preference_id = Column(String, ForeignKey("inspection_preferences.id"), nullable=False, index=True)
    slot_date = Column(Date, nullable=False, index=True)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    label = Column(String, nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_inspection_pref_slots_pref_date", "preference_id", "slot_date"),
    )


class InspectionAvailabilityOverride(Base):
    __tablename__ = "inspection_availability_overrides"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    override_date = Column(Date, nullable=False, index=True)
    is_available = Column(Boolean, nullable=False, default=True)
    note = Column(String, nullable=True)
    source = Column(String, nullable=False, default="cat_ipad")
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("uq_inspection_availability_override_user_date", "user_id", "override_date", unique=True),
    )


class InspectionAvailabilityWindow(Base):
    __tablename__ = "inspection_availability_windows"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    override_id = Column(String, ForeignKey("inspection_availability_overrides.id"), nullable=False, index=True)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_inspection_availability_windows_override", "override_id", "sort_order"),
    )


class InspectionRouteProposal(Base):
    __tablename__ = "inspection_route_proposals"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    owner_user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    plan_date = Column(Date, nullable=False, index=True)
    status = Column(String, nullable=False, default="proposed", index=True)
    generated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    review_deadline = Column(DateTime(timezone=True), nullable=True, index=True)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    accepted_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    rejection_reason_code = Column(String, nullable=True)
    rejection_reason = Column(String, nullable=True)
    source = Column(String, nullable=False, default="inspection_automation")
    has_configured_poi = Column(Boolean, nullable=False, default=False)
    total_distance_km = Column(Numeric(10, 2), nullable=False, default=0)
    total_duration_minutes = Column(Integer, nullable=False, default=0)
    tenant_names_json = Column(JSON, nullable=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_inspection_route_proposals_tenant_plan", "tenant_id", "plan_date"),
    )


class InspectionRouteStop(Base):
    __tablename__ = "inspection_route_stops"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    proposal_id = Column(String, ForeignKey("inspection_route_proposals.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    claim_reference = Column(String, nullable=True)
    starts_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    municipality = Column(String, nullable=True)
    province = Column(String, nullable=True)
    region = Column(String, nullable=True)
    latitude = Column(Numeric(10, 6), nullable=True)
    longitude = Column(Numeric(10, 6), nullable=True)
    masked_location = Column(String, nullable=True)
    outside_zone = Column(Boolean, nullable=False, default=False)
    distance_from_previous_km = Column(Numeric(10, 2), nullable=False, default=0)
    duration_minutes = Column(Integer, nullable=False, default=0)
    asset_count = Column(Integer, nullable=False, default=1)
    complexity = Column(String, nullable=True)
    manually_fixed = Column(Boolean, nullable=False, default=False)
    note = Column(String, nullable=True)
    preferred_windows_json = Column(JSON, nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_inspection_route_stops_proposal_order", "proposal_id", "sort_order"),
        Index("idx_inspection_route_stops_claim", "claim_id", "proposal_id"),
    )


class InspectionTenantAutomationState(Base):
    __tablename__ = "inspection_tenant_automation_states"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    last_route_generation_date = Column(Date, nullable=True)
    last_route_generation_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("uq_inspection_tenant_automation_state_tenant", "tenant_id", unique=True),
    )
