"""
Automation scaffolding for the CAT inspection workflow.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone
import logging
import math
from typing import Optional
from zoneinfo import ZoneInfo
import uuid

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.inspection import (
    InspectionAvailabilityOverride,
    InspectionAvailabilityWindow,
    InspectionPreference,
    InspectionPreferenceSlot,
    InspectionRouteProposal,
    InspectionRouteStop,
    InspectionTenantAutomationState,
)
from app.models.planning import CalendarEvent, UserWorkSchedule
from app.models.role import Role, user_roles
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.inspection import (
    InspectionAvailabilityCommitmentResponse,
    InspectionAvailabilityDayResponse,
    InspectionAvailabilityMonthResponse,
    InspectionAvailabilityOverrideUpsert,
    InspectionPreferredSlotInput,
    InspectionAvailabilityWindowInput,
    InspectionManualAppointmentCreate,
    InspectionSchedulingPreferencesUpsert,
)
from app.schemas.tenant_settings import TenantCATMunicipality, TenantCATPOI, TenantCATSettingsPayload
from app.core.claim_status import ClaimStatus
from app.services.claim_service import ClaimService
from app.services.cat_duration_stats_service import (
    bucket_for_asset_count,
    load_median_minutes,
)
from app.services.state_service import StateService, has_substato
from app.services.travel_time_service import (
    Coordinate,
    TravelEstimate,
    TravelTimeService,
)

logger = logging.getLogger(__name__)

LOCAL_TIMEZONE = ZoneInfo("Europe/Rome")
ROUTE_PROPOSAL_EVENT_TYPE = "cat_route_proposal"
CONFIRMED_APPOINTMENT_EVENT_TYPE = "inspection_appointment"
INSPECTION_LEAD_DAYS = 2
# Stati da cui il sinistro può auto-entrare nel workflow di scheduling CAT.
AUTO_ENTRY_STATES = {
    ClaimStatus.ISTRUZIONE.value,
    ClaimStatus.PRIMO_CONTATTO.value,
    ClaimStatus.SECONDO_CONTATTO.value,
    ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value,
    ClaimStatus.SOPRALLUOGO.value,
}
# Stato unico per la fase di sopralluogo: le sotto-fasi sono substati
# ("da_fissare", "fissato", "confermato", "da_concordare", "da_rifissare").
CAT_ACTIVE_STATES = {ClaimStatus.SOPRALLUOGO.value}


@dataclass
class TechnicianContext:
    user_id: str
    email: str
    full_name: str
    latitude: Optional[float]
    longitude: Optional[float]
    comune: str
    provincia: str
    regione: str
    assigned_municipalities: set[str]
    note: str = ""
    has_configured_poi: bool = False
    busy_intervals: list[tuple[datetime, datetime]] = field(default_factory=list)
    provisional_stops: list["ProposedStop"] = field(default_factory=list)


@dataclass
class ClaimPlanningContext:
    claim: Claim
    reference: str
    municipality: str
    province: str
    region: str
    address_line: Optional[str]
    latitude: Optional[float]
    longitude: Optional[float]
    duration_minutes: int
    preferred_windows: list[dict]


@dataclass
class ProposedStop:
    claim_id: str
    claim_reference: Optional[str]
    starts_at: datetime
    ends_at: datetime
    municipality: str
    province: str
    region: str
    masked_location: str
    latitude: Optional[float]
    longitude: Optional[float]
    outside_zone: bool
    distance_from_previous_km: float
    duration_minutes: int
    preferred_start: datetime


class InspectionWorkflowService:
    @staticmethod
    def _metadata(claim: Claim) -> dict:
        return dict(claim.metadata_json or {})

    @staticmethod
    def _save_metadata(claim: Claim, metadata: dict) -> None:
        claim.metadata_json = metadata or None

    @staticmethod
    def _parse_datetime(raw_value: object) -> Optional[datetime]:
        if isinstance(raw_value, datetime):
            return raw_value if raw_value.tzinfo else raw_value.replace(tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
        if not isinstance(raw_value, str) or not raw_value.strip():
            return None
        candidate = raw_value.strip()
        if candidate.endswith("Z"):
            candidate = candidate[:-1] + "+00:00"
        try:
            parsed = datetime.fromisoformat(candidate)
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=LOCAL_TIMEZONE)
        return parsed.astimezone(timezone.utc)

    @staticmethod
    def _parse_date(raw_value: object) -> Optional[date]:
        if isinstance(raw_value, date):
            return raw_value
        if not isinstance(raw_value, str) or not raw_value.strip():
            return None
        try:
            return date.fromisoformat(raw_value.strip())
        except ValueError:
            return None

    @staticmethod
    def _parse_time(raw_value: object) -> Optional[time]:
        if isinstance(raw_value, time):
            return raw_value
        if not isinstance(raw_value, str) or not raw_value.strip():
            return None
        try:
            return time.fromisoformat(raw_value.strip())
        except ValueError:
            return None

    @staticmethod
    def _combine_local(plan_date: date, plan_time: time) -> datetime:
        combined = datetime.combine(plan_date, plan_time)
        return combined.replace(tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)

    @staticmethod
    def _normalize_text(value: Optional[str]) -> str:
        return (value or "").strip().lower()

    @staticmethod
    def _masked_location(municipality: str, province: str, region: str) -> str:
        parts = [value for value in [municipality, province, region] if value]
        return ", ".join(parts)

    @staticmethod
    def _claim_reference(claim: Claim) -> str:
        return claim.external_ref or claim.numero_sinistro or claim.id

    @staticmethod
    def _safe_float(raw_value: object) -> Optional[float]:
        try:
            if raw_value is None:
                return None
            return float(raw_value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _nearest_municipality(
        cat_settings: TenantCATSettingsPayload,
        latitude: Optional[float],
        longitude: Optional[float],
    ) -> Optional[TenantCATMunicipality]:
        if latitude is None or longitude is None:
            return None
        nearest: Optional[TenantCATMunicipality] = None
        nearest_distance: Optional[float] = None
        for municipality in cat_settings.municipalities:
            distance_km = InspectionWorkflowService._haversine_km(
                latitude,
                longitude,
                municipality.latitude,
                municipality.longitude,
            )
            if nearest_distance is None or distance_km < nearest_distance:
                nearest = municipality
                nearest_distance = distance_km
        return nearest

    @staticmethod
    def _location_defaults_for_claim(
        claim: Claim,
        cat_settings: TenantCATSettingsPayload,
    ) -> dict:
        preferences = InspectionWorkflowService._preferences_metadata(claim)
        metadata = InspectionWorkflowService._metadata(claim)

        latitude = InspectionWorkflowService._safe_float(preferences.get("latitude"))
        if latitude is None:
            latitude = InspectionWorkflowService._safe_float(metadata.get("inspection_latitude"))
        longitude = InspectionWorkflowService._safe_float(preferences.get("longitude"))
        if longitude is None:
            longitude = InspectionWorkflowService._safe_float(metadata.get("inspection_longitude"))

        municipality = (preferences.get("municipality") or metadata.get("inspection_municipality") or "").strip()
        province = (preferences.get("province") or metadata.get("inspection_province") or "").strip()
        region = (preferences.get("region") or metadata.get("inspection_region") or "").strip()

        nearest = InspectionWorkflowService._nearest_municipality(cat_settings, latitude, longitude)
        if nearest is not None:
            municipality = municipality or nearest.comune
            province = province or nearest.provincia
            region = region or nearest.regione

        return {
            "address_line": (
                (preferences.get("address_line") or "").strip()
                or (claim.indirizzo_assicurato or "").strip()
                or (claim.ubicazione_note or "").strip()
                or None
            ),
            "municipality": municipality or None,
            "province": province or None,
            "region": region or None,
            "latitude": latitude,
            "longitude": longitude,
            "confirmed_at": InspectionWorkflowService._parse_datetime(preferences.get("confirmed_at")),
        }

    @staticmethod
    def _selected_slot_payload(preferences: dict) -> list[dict]:
        raw_slots = preferences.get("preferred_slots")
        if not isinstance(raw_slots, list):
            return []

        slots: list[dict] = []
        for raw_slot in raw_slots:
            if not isinstance(raw_slot, dict):
                continue
            slot_date = InspectionWorkflowService._parse_date(raw_slot.get("date"))
            slot_start = InspectionWorkflowService._parse_time(raw_slot.get("start_time"))
            slot_end = InspectionWorkflowService._parse_time(raw_slot.get("end_time"))
            if slot_date is None or slot_start is None or slot_end is None:
                continue
            starts_at = InspectionWorkflowService._combine_local(slot_date, slot_start)
            ends_at = InspectionWorkflowService._combine_local(slot_date, slot_end)
            slots.append(
                {
                    "id": starts_at.isoformat(),
                    "date": slot_date.isoformat(),
                    "start_at": starts_at,
                    "end_at": ends_at,
                    "label": raw_slot.get("label")
                    or f"{slot_start.strftime('%H:%M')} - {slot_end.strftime('%H:%M')}",
                }
            )
        return sorted(slots, key=lambda item: item["start_at"])

    INSPECTION_DURATION_BASE_MINUTES = 20
    INSPECTION_DURATION_FREE_ASSET_THRESHOLD = 3
    INSPECTION_DURATION_PER_EXTRA_ASSET_MINUTES = 5
    INSPECTION_DURATION_SAFETY_MARGIN_MINUTES = 5
    INSPECTION_DURATION_MAX_MINUTES = 60
    INSPECTION_DURATION_MIN_MINUTES = 15

    @staticmethod
    def _asset_count_for_claim(claim: Claim) -> int:
        metadata = InspectionWorkflowService._metadata(claim)
        raw = metadata.get("numero_beni")
        try:
            value = int(raw)
        except (TypeError, ValueError):
            return 1
        return max(1, value)

    @staticmethod
    def _estimate_default_duration_minutes(asset_count: int) -> int:
        extra = max(0, asset_count - InspectionWorkflowService.INSPECTION_DURATION_FREE_ASSET_THRESHOLD)
        base = (
            InspectionWorkflowService.INSPECTION_DURATION_BASE_MINUTES
            + extra * InspectionWorkflowService.INSPECTION_DURATION_PER_EXTRA_ASSET_MINUTES
        )
        return min(
            InspectionWorkflowService.INSPECTION_DURATION_MAX_MINUTES,
            max(
                InspectionWorkflowService.INSPECTION_DURATION_MIN_MINUTES,
                base + InspectionWorkflowService.INSPECTION_DURATION_SAFETY_MARGIN_MINUTES,
            ),
        )

    @staticmethod
    def _resolve_inspection_duration_minutes(
        asset_count: int,
        cat_stats_map: Optional[dict[tuple[str, int], int]] = None,
        cat_user_id: Optional[str] = None,
    ) -> int:
        default = InspectionWorkflowService._estimate_default_duration_minutes(asset_count)
        if not cat_stats_map or not cat_user_id:
            return default
        bucket = bucket_for_asset_count(asset_count)
        cat_minutes = cat_stats_map.get((cat_user_id, bucket))
        if cat_minutes is None:
            return default
        return min(
            InspectionWorkflowService.INSPECTION_DURATION_MAX_MINUTES,
            max(
                InspectionWorkflowService.INSPECTION_DURATION_MIN_MINUTES,
                cat_minutes + InspectionWorkflowService.INSPECTION_DURATION_SAFETY_MARGIN_MINUTES,
            ),
        )

    @staticmethod
    def _duration_minutes_for_claim(claim: Claim, preferences: dict) -> int:
        requested = preferences.get("requested_duration_minutes")
        if isinstance(requested, int):
            return min(
                InspectionWorkflowService.INSPECTION_DURATION_MAX_MINUTES,
                max(InspectionWorkflowService.INSPECTION_DURATION_MIN_MINUTES, requested),
            )
        asset_count = InspectionWorkflowService._asset_count_for_claim(claim)
        return InspectionWorkflowService._estimate_default_duration_minutes(asset_count)

    @staticmethod
    def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        radius = 6371.0
        lat1_rad = math.radians(lat1)
        lat2_rad = math.radians(lat2)
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
        )
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return radius * c

    @staticmethod
    def _estimate_travel_minutes(distance_km: float) -> int:
        if distance_km <= 0.5:
            return 0
        return max(10, math.ceil((distance_km / 35.0) * 60))

    @staticmethod
    def _weekday_candidates(target_date: date) -> set[int]:
        python_weekday = target_date.weekday()
        apple_weekday = ((python_weekday + 1) % 7) + 1
        return {python_weekday, apple_weekday}

    @staticmethod
    async def _create_claim_event(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        event_type: str,
        data: dict,
        *,
        source: str = "system",
        actor_user_id: Optional[str] = None,
    ) -> None:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim_id,
                event_type=event_type,
                actor_user_id=actor_user_id,
                data_json=data,
                source=source,
            )
        )

    @staticmethod
    async def _get_claim_or_raise(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
    ) -> Claim:
        claim = await ClaimService.get_claim(db, tenant_id, claim_id)
        if not claim:
            raise ValueError("Claim not found")
        return claim

    @staticmethod
    async def _load_tenant_cat_settings(
        db: AsyncSession,
        tenant_id: str,
    ) -> tuple[Tenant, TenantCATSettingsPayload]:
        result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
        tenant = result.scalar_one_or_none()
        if tenant is None:
            raise ValueError("Tenant not found")

        raw_settings = (tenant.settings_json or {}).get("cat_settings") or {}
        try:
            cat_settings = TenantCATSettingsPayload.model_validate(raw_settings)
        except Exception:
            cat_settings = TenantCATSettingsPayload()
        return tenant, cat_settings

    @staticmethod
    async def _fetch_cat_users(
        db: AsyncSession,
        tenant_id: str,
    ) -> list[User]:
        result = await db.execute(
            select(User)
            .join(user_roles, user_roles.c.user_id == User.id)
            .join(Role, Role.id == user_roles.c.role_id)
            .where(
                User.tenant_id == tenant_id,
                User.is_active == True,
                Role.name == "cat",
            )
        )
        return list({user.id: user for user in result.scalars().all()}.values())

    @staticmethod
    async def _fetch_route_event(
        db: AsyncSession,
        event_id: str,
    ) -> Optional[CalendarEvent]:
        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.id == event_id,
                CalendarEvent.event_type == ROUTE_PROPOSAL_EVENT_TYPE,
            )
        )
        return result.scalar_one_or_none()

    @staticmethod
    def _route_metadata(event: CalendarEvent) -> dict:
        return dict(event.metadata_json or {})

    @staticmethod
    def _route_projection_metadata(proposal: InspectionRouteProposal) -> dict:
        return dict(proposal.metadata_json or {})

    @staticmethod
    def _preferences_metadata(claim: Claim) -> dict:
        metadata = InspectionWorkflowService._metadata(claim)
        value = metadata.get("inspection_preferences")
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _assignment_metadata(claim: Claim) -> dict:
        metadata = InspectionWorkflowService._metadata(claim)
        value = metadata.get("inspection_assignment")
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _automation_metadata(claim: Claim) -> dict:
        metadata = InspectionWorkflowService._metadata(claim)
        value = metadata.get("inspection_automation")
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _user_settings(user: User) -> dict:
        return dict(user.settings_json or {})

    @staticmethod
    def _availability_overrides(user: User) -> dict:
        settings_json = InspectionWorkflowService._user_settings(user)
        value = settings_json.get("inspection_availability_overrides")
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _serialize_availability_override(
        payload: InspectionAvailabilityOverrideUpsert,
    ) -> dict:
        return {
            "is_available": payload.is_available,
            "note": payload.note,
            "windows": [
                {
                    "start_time": window.start_time.isoformat(timespec="minutes"),
                    "end_time": window.end_time.isoformat(timespec="minutes"),
                }
                for window in payload.windows
            ],
        }

    @staticmethod
    def _availability_windows_from_override(raw_override: dict) -> list[tuple[time, time]]:
        raw_windows = raw_override.get("windows")
        if not isinstance(raw_windows, list):
            return []
        windows: list[tuple[time, time]] = []
        for raw_window in raw_windows:
            if not isinstance(raw_window, dict):
                continue
            start_time = InspectionWorkflowService._parse_time(raw_window.get("start_time"))
            end_time = InspectionWorkflowService._parse_time(raw_window.get("end_time"))
            if start_time and end_time and end_time > start_time:
                windows.append((start_time, end_time))
        return sorted(windows, key=lambda item: item[0])

    @staticmethod
    async def _load_preference_projection(
        db: AsyncSession,
        claim_id: str,
    ) -> tuple[Optional[InspectionPreference], list[InspectionPreferenceSlot]]:
        result = await db.execute(
            select(InspectionPreference).where(InspectionPreference.claim_id == claim_id)
        )
        preference = result.scalar_one_or_none()
        if preference is None:
            return None, []
        slots_result = await db.execute(
            select(InspectionPreferenceSlot)
            .where(InspectionPreferenceSlot.preference_id == preference.id)
            .order_by(InspectionPreferenceSlot.slot_date.asc(), InspectionPreferenceSlot.sort_order.asc())
        )
        return preference, list(slots_result.scalars().all())

    @staticmethod
    async def _upsert_preference_projection(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        *,
        address_line: Optional[str],
        municipality: Optional[str],
        province: Optional[str],
        region: Optional[str],
        latitude: Optional[float],
        longitude: Optional[float],
        confirmed_at: Optional[datetime],
        requested_duration_minutes: Optional[int],
        notes: Optional[str],
        source: str,
        preferred_slots: list[InspectionPreferredSlotInput],
    ) -> InspectionPreference:
        preference, existing_slots = await InspectionWorkflowService._load_preference_projection(db, claim.id)
        if preference is None:
            preference = InspectionPreference(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
            )
            db.add(preference)
        preference.address_line = address_line
        preference.municipality = municipality
        preference.province = province
        preference.region = region
        preference.latitude = latitude
        preference.longitude = longitude
        preference.confirmed_at = confirmed_at
        preference.requested_duration_minutes = requested_duration_minutes
        preference.notes = notes
        preference.source = source

        for slot in existing_slots:
            await db.delete(slot)
        for index, slot in enumerate(preferred_slots):
            db.add(
                InspectionPreferenceSlot(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    preference_id=preference.id,
                    slot_date=slot.date,
                    start_time=slot.start_time,
                    end_time=slot.end_time,
                    label=slot.label,
                    sort_order=index,
                )
            )
        await db.flush()
        return preference

    @staticmethod
    async def _load_availability_override_projection_map(
        db: AsyncSession,
        tenant_id: str,
        owner_user_id: str,
        range_start: date,
        range_end_exclusive: date,
    ) -> dict[date, tuple[InspectionAvailabilityOverride, list[InspectionAvailabilityWindow]]]:
        result = await db.execute(
            select(InspectionAvailabilityOverride)
            .where(
                InspectionAvailabilityOverride.tenant_id == tenant_id,
                InspectionAvailabilityOverride.user_id == owner_user_id,
                InspectionAvailabilityOverride.override_date >= range_start,
                InspectionAvailabilityOverride.override_date < range_end_exclusive,
            )
            .order_by(InspectionAvailabilityOverride.override_date.asc())
        )
        overrides = list(result.scalars().all())
        if not overrides:
            return {}

        override_ids = [item.id for item in overrides]
        windows_result = await db.execute(
            select(InspectionAvailabilityWindow)
            .where(InspectionAvailabilityWindow.override_id.in_(override_ids))
            .order_by(InspectionAvailabilityWindow.override_id.asc(), InspectionAvailabilityWindow.sort_order.asc())
        )
        windows_by_override: dict[str, list[InspectionAvailabilityWindow]] = {}
        for window in windows_result.scalars().all():
            windows_by_override.setdefault(window.override_id, []).append(window)
        return {
            override.override_date: (override, windows_by_override.get(override.id, []))
            for override in overrides
        }

    @staticmethod
    async def _upsert_availability_override_projection(
        db: AsyncSession,
        tenant_id: str,
        owner_user_id: str,
        target_date: date,
        payload: InspectionAvailabilityOverrideUpsert,
        *,
        source: str,
    ) -> InspectionAvailabilityOverride:
        result = await db.execute(
            select(InspectionAvailabilityOverride).where(
                InspectionAvailabilityOverride.tenant_id == tenant_id,
                InspectionAvailabilityOverride.user_id == owner_user_id,
                InspectionAvailabilityOverride.override_date == target_date,
            )
        )
        override = result.scalar_one_or_none()
        if override is None:
            override = InspectionAvailabilityOverride(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                user_id=owner_user_id,
                override_date=target_date,
            )
            db.add(override)
        override.is_available = payload.is_available
        override.note = payload.note
        override.source = source

        windows_result = await db.execute(
            select(InspectionAvailabilityWindow).where(InspectionAvailabilityWindow.override_id == override.id)
        )
        for window in windows_result.scalars().all():
            await db.delete(window)
        await db.flush()
        for index, window in enumerate(payload.windows):
            db.add(
                InspectionAvailabilityWindow(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    override_id=override.id,
                    start_time=window.start_time,
                    end_time=window.end_time,
                    sort_order=index,
                )
            )
        await db.flush()
        return override

    @staticmethod
    async def _fetch_route_proposal(
        db: AsyncSession,
        proposal_id: str,
    ) -> Optional[InspectionRouteProposal]:
        result = await db.execute(
            select(InspectionRouteProposal).where(InspectionRouteProposal.id == proposal_id)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def _fetch_route_stops(
        db: AsyncSession,
        proposal_id: str,
    ) -> list[InspectionRouteStop]:
        result = await db.execute(
            select(InspectionRouteStop)
            .where(InspectionRouteStop.proposal_id == proposal_id)
            .order_by(InspectionRouteStop.sort_order.asc(), InspectionRouteStop.starts_at.asc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def _sync_route_projection(
        db: AsyncSession,
        *,
        proposal_id: str,
        tenant_id: str,
        owner_user_id: str,
        title: str,
        description: Optional[str],
        plan_date: date,
        status: str,
        generated_at: datetime,
        review_deadline: Optional[datetime],
        source: str,
        has_configured_poi: bool,
        total_distance_km: float,
        total_duration_minutes: int,
        tenant_names: list[str],
        metadata: dict,
        stops: list[dict],
    ) -> InspectionRouteProposal:
        proposal = await InspectionWorkflowService._fetch_route_proposal(db, proposal_id)
        if proposal is None:
            proposal = InspectionRouteProposal(
                id=proposal_id,
                tenant_id=tenant_id,
                owner_user_id=owner_user_id,
            )
            db.add(proposal)
        proposal.title = title
        proposal.description = description
        proposal.plan_date = plan_date
        proposal.status = status
        proposal.generated_at = generated_at
        proposal.review_deadline = review_deadline
        proposal.source = source
        proposal.has_configured_poi = has_configured_poi
        proposal.total_distance_km = total_distance_km
        proposal.total_duration_minutes = total_duration_minutes
        proposal.tenant_names_json = tenant_names
        proposal.metadata_json = metadata or None
        if status == "accepted":
            proposal.accepted_at = InspectionWorkflowService._parse_datetime(metadata.get("accepted_at"))
            proposal.accepted_by_user_id = metadata.get("accepted_by_user_id")
        else:
            proposal.accepted_at = None
            proposal.accepted_by_user_id = None
        proposal.rejection_reason_code = metadata.get("rejection_reason_code")
        proposal.rejection_reason = metadata.get("rejection_reason")

        existing_stops = await InspectionWorkflowService._fetch_route_stops(db, proposal_id)
        for existing_stop in existing_stops:
            await db.delete(existing_stop)
        await db.flush()
        for index, stop in enumerate(stops):
            db.add(
                InspectionRouteStop(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    proposal_id=proposal_id,
                    claim_id=stop["claim_id"],
                    claim_reference=stop.get("claim_reference"),
                    starts_at=InspectionWorkflowService._parse_datetime(stop.get("starts_at")) or generated_at,
                    ends_at=InspectionWorkflowService._parse_datetime(stop.get("ends_at")) or generated_at,
                    municipality=stop.get("municipality"),
                    province=stop.get("province"),
                    region=stop.get("region"),
                    latitude=stop.get("latitude"),
                    longitude=stop.get("longitude"),
                    masked_location=stop.get("masked_location"),
                    outside_zone=bool(stop.get("outside_zone")),
                    distance_from_previous_km=float(stop.get("distance_from_previous_km") or 0),
                    duration_minutes=int(stop.get("duration_minutes") or 0),
                    asset_count=int(stop.get("asset_count") or 0),
                    complexity=stop.get("complexity"),
                    manually_fixed=bool(stop.get("manually_fixed")),
                    note=stop.get("note"),
                    preferred_windows_json=stop.get("preferred_windows") or [],
                    sort_order=index,
                )
            )
        await db.flush()
        return proposal

    @staticmethod
    async def _set_route_projection_status(
        db: AsyncSession,
        proposal_id: str,
        *,
        status: str,
        metadata: dict,
    ) -> None:
        proposal = await InspectionWorkflowService._fetch_route_proposal(db, proposal_id)
        if proposal is None:
            return
        proposal.status = status
        proposal.metadata_json = metadata or None
        proposal.review_deadline = InspectionWorkflowService._parse_datetime(metadata.get("review_deadline"))
        proposal.accepted_at = InspectionWorkflowService._parse_datetime(metadata.get("accepted_at"))
        proposal.accepted_by_user_id = metadata.get("accepted_by_user_id")
        proposal.rejection_reason_code = metadata.get("rejection_reason_code")
        proposal.rejection_reason = metadata.get("rejection_reason")

    @staticmethod
    async def _list_route_projection_records(
        db: AsyncSession,
        tenant_id: str,
        *,
        owner_user_id: Optional[str] = None,
        status_filter: Optional[str] = None,
        plan_date: Optional[date] = None,
    ) -> list[InspectionRouteProposal]:
        query = select(InspectionRouteProposal).where(InspectionRouteProposal.tenant_id == tenant_id)
        if owner_user_id:
            query = query.where(InspectionRouteProposal.owner_user_id == owner_user_id)
        if status_filter:
            query = query.where(InspectionRouteProposal.status == status_filter)
        if plan_date:
            query = query.where(InspectionRouteProposal.plan_date == plan_date)
        result = await db.execute(
            query.order_by(InspectionRouteProposal.plan_date.asc(), InspectionRouteProposal.generated_at.asc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def _get_or_create_automation_state(
        db: AsyncSession,
        tenant_id: str,
    ) -> InspectionTenantAutomationState:
        result = await db.execute(
            select(InspectionTenantAutomationState).where(
                InspectionTenantAutomationState.tenant_id == tenant_id
            )
        )
        state = result.scalar_one_or_none()
        if state is None:
            state = InspectionTenantAutomationState(id=str(uuid.uuid4()), tenant_id=tenant_id)
            db.add(state)
            await db.flush()
        return state

    @staticmethod
    def _merge_contiguous_windows(windows: list[dict]) -> list[dict]:
        """Fonde finestre adiacenti (gap <= 60s) in una sola.

        L'assicurato può selezionare slot consecutivi (es. 09-11 + 11-13):
        per noi diventa una sola finestra 09-13 da cui pescare qualunque orario.
        """
        if not windows:
            return []
        ordered = sorted(windows, key=lambda item: item["preferred_start"])
        merged: list[dict] = [dict(ordered[0])]
        for window in ordered[1:]:
            current = merged[-1]
            gap = (window["preferred_start"] - current["preferred_end"]).total_seconds()
            if abs(gap) <= 60:
                current["preferred_end"] = max(current["preferred_end"], window["preferred_end"])
                current["allowed_end"] = current["preferred_end"]
                current["slot_minutes"] = int(
                    (current["preferred_end"] - current["preferred_start"]).total_seconds() / 60
                )
                merged_labels = [
                    label
                    for label in (current.get("label"), window.get("label"))
                    if label
                ]
                if merged_labels:
                    current["label"] = " + ".join(dict.fromkeys(merged_labels))
            else:
                merged.append(dict(window))
        return merged

    @staticmethod
    def _preferred_windows_for_plan_date(
        claim: Claim,
        plan_date: date,
        tolerance_percent: int,
    ) -> list[dict]:
        preferences = InspectionWorkflowService._preferences_metadata(claim)
        slots = preferences.get("preferred_slots")
        if not isinstance(slots, list):
            return []

        # `tolerance_percent` è stato mantenuto in firma per compatibilità ma
        # non amplia più la finestra: l'orario proposto deve sempre cadere
        # dentro lo slot scelto dall'assicurato (hard constraint).
        _ = tolerance_percent

        windows: list[dict] = []
        for raw_slot in slots:
            if not isinstance(raw_slot, dict):
                continue
            slot_date = InspectionWorkflowService._parse_date(raw_slot.get("date"))
            start_time = InspectionWorkflowService._parse_time(raw_slot.get("start_time"))
            end_time = InspectionWorkflowService._parse_time(raw_slot.get("end_time"))
            if slot_date != plan_date or not start_time or not end_time:
                continue

            preferred_start = InspectionWorkflowService._combine_local(plan_date, start_time)
            preferred_end = InspectionWorkflowService._combine_local(plan_date, end_time)
            if preferred_end <= preferred_start:
                continue

            slot_minutes = max(1, int((preferred_end - preferred_start).total_seconds() / 60))
            windows.append(
                {
                    "label": raw_slot.get("label"),
                    "preferred_start": preferred_start,
                    "preferred_end": preferred_end,
                    "allowed_start": preferred_start,
                    "allowed_end": preferred_end,
                    "slot_minutes": slot_minutes,
                    "tolerance_minutes": 0,
                }
            )
        return InspectionWorkflowService._merge_contiguous_windows(windows)

    @staticmethod
    def _build_claim_context(
        claim: Claim,
        plan_date: date,
        tolerance_percent: int,
    ) -> Optional[ClaimPlanningContext]:
        preferences = InspectionWorkflowService._preferences_metadata(claim)
        preferred_windows = InspectionWorkflowService._preferred_windows_for_plan_date(
            claim,
            plan_date,
            tolerance_percent,
        )
        if not preferred_windows:
            return None

        reference = claim.external_ref or claim.numero_sinistro or claim.id
        municipality = preferences.get("municipality") or ""
        province = preferences.get("province") or ""
        region = preferences.get("region") or ""
        return ClaimPlanningContext(
            claim=claim,
            reference=reference,
            municipality=municipality,
            province=province,
            region=region,
            address_line=preferences.get("address_line"),
            latitude=preferences.get("latitude"),
            longitude=preferences.get("longitude"),
            duration_minutes=InspectionWorkflowService._duration_minutes_for_claim(claim, preferences),
            preferred_windows=preferred_windows,
        )

    @staticmethod
    def _build_location_claim_context(
        claim: Claim,
        location: dict,
        duration_minutes: int,
    ) -> ClaimPlanningContext:
        return ClaimPlanningContext(
            claim=claim,
            reference=InspectionWorkflowService._claim_reference(claim),
            municipality=location.get("municipality") or "",
            province=location.get("province") or "",
            region=location.get("region") or "",
            address_line=location.get("address_line"),
            latitude=location.get("latitude"),
            longitude=location.get("longitude"),
            duration_minutes=duration_minutes,
            preferred_windows=[],
        )

    @staticmethod
    async def _load_technician_contexts(
        db: AsyncSession,
        tenant_id: str,
        cat_settings: TenantCATSettingsPayload,
        plan_date: date,
    ) -> list[TechnicianContext]:
        poi_by_email = {
            poi.email.strip().lower(): poi
            for poi in cat_settings.technicians
            if poi.email.strip()
        }
        users = await InspectionWorkflowService._fetch_cat_users(db, tenant_id)
        if not users:
            return []

        contexts: list[TechnicianContext] = []
        for user in users:
            email = user.email.strip().lower()
            poi: Optional[TenantCATPOI] = poi_by_email.get(email)
            contexts.append(
                TechnicianContext(
                    user_id=user.id,
                    email=email,
                    full_name=user.full_name,
                    latitude=poi.latitude if poi else None,
                    longitude=poi.longitude if poi else None,
                    comune=poi.comune if poi else "",
                    provincia=poi.provincia if poi else "",
                    regione=poi.regione if poi else "",
                    assigned_municipalities={
                        InspectionWorkflowService._normalize_text(item)
                        for item in (poi.assigned_municipalities if poi else [])
                        if InspectionWorkflowService._normalize_text(item)
                    },
                    note=poi.note if poi else "",
                    has_configured_poi=poi is not None,
                )
            )

        weekday_candidates = InspectionWorkflowService._weekday_candidates(plan_date)
        range_start = datetime.combine(plan_date, time.min, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
        range_end = datetime.combine(plan_date + timedelta(days=1), time.min, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)

        user_ids = [context.user_id for context in contexts]
        schedule_result = await db.execute(
            select(UserWorkSchedule).where(
                UserWorkSchedule.user_id.in_(user_ids),
                UserWorkSchedule.weekday.in_(weekday_candidates),
                or_(UserWorkSchedule.effective_from.is_(None), UserWorkSchedule.effective_from <= plan_date),
                or_(UserWorkSchedule.effective_to.is_(None), UserWorkSchedule.effective_to >= plan_date),
            )
        )
        schedules_by_user: dict[str, list[tuple[datetime, datetime]]] = {user_id: [] for user_id in user_ids}
        for schedule in schedule_result.scalars().all():
            if schedule.location and InspectionWorkflowService._normalize_text(schedule.location) == "remote":
                continue
            metadata = schedule.metadata_json or {}
            if InspectionWorkflowService._normalize_text(str(metadata.get("place", ""))) == "remote":
                continue
            start_at = datetime.combine(plan_date, schedule.start_time, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
            end_at = datetime.combine(plan_date, schedule.end_time, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
            if end_at > start_at:
                schedules_by_user[schedule.user_id].append((start_at, end_at))

        date_key = plan_date.isoformat()
        overrides_by_user: dict[str, dict] = {}
        for user in users:
            raw_override = InspectionWorkflowService._availability_overrides(user).get(date_key)
            if isinstance(raw_override, dict):
                overrides_by_user[user.id] = raw_override

        busy_result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.owner_user_id.in_(user_ids),
                CalendarEvent.starts_at < range_end,
                CalendarEvent.ends_at > range_start,
                CalendarEvent.status.in_(["confirmed", "proposed", "accepted"]),
            )
        )
        busy_by_user: dict[str, list[tuple[datetime, datetime]]] = {user_id: [] for user_id in user_ids}
        for event in busy_result.scalars().all():
            if event.event_type == ROUTE_PROPOSAL_EVENT_TYPE and event.status in {"rejected", "expired", "superseded"}:
                continue
            busy_by_user[event.owner_user_id].append((event.starts_at, event.ends_at))

        for context in contexts:
            override = overrides_by_user.get(context.user_id)
            if override is not None:
                if bool(override.get("is_available")):
                    working_intervals = [
                        (
                            datetime.combine(plan_date, start_time, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc),
                            datetime.combine(plan_date, end_time, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc),
                        )
                        for start_time, end_time in InspectionWorkflowService._availability_windows_from_override(override)
                    ]
                else:
                    working_intervals = []
            else:
                working_intervals = schedules_by_user.get(context.user_id, [])
            context.busy_intervals = busy_by_user.get(context.user_id, [])
            context.provisional_stops = []
            setattr(context, "working_intervals", sorted(working_intervals, key=lambda item: item[0]))
        return contexts

    @staticmethod
    async def _candidate_cat_contacts_for_location(
        db: AsyncSession,
        tenant_id: str,
        cat_settings: TenantCATSettingsPayload,
        location: dict,
    ) -> list[dict]:
        users = await InspectionWorkflowService._fetch_cat_users(db, tenant_id)
        if not users:
            return []

        poi_by_email = {
            poi.email.strip().lower(): poi
            for poi in cat_settings.technicians
            if poi.email.strip()
        }
        municipality = InspectionWorkflowService._normalize_text(location.get("municipality"))
        latitude = location.get("latitude")
        longitude = location.get("longitude")
        max_distance = cat_settings.planner.max_outside_zone_kilometers

        ranked: list[tuple[int, float, User, Optional[TenantCATPOI]]] = []
        for user in users:
            poi = poi_by_email.get(user.email.strip().lower())
            assigned = {
                InspectionWorkflowService._normalize_text(item)
                for item in (poi.assigned_municipalities if poi else [])
                if InspectionWorkflowService._normalize_text(item)
            }
            if municipality and municipality in assigned:
                ranked.append((0, 0.0, user, poi))
                continue

            if (
                poi is not None
                and latitude is not None
                and longitude is not None
            ):
                distance_km = InspectionWorkflowService._haversine_km(
                    latitude,
                    longitude,
                    poi.latitude,
                    poi.longitude,
                )
                if distance_km <= max_distance:
                    ranked.append((1, distance_km, user, poi))
                    continue

            ranked.append((2, float(max_distance + 1), user, poi))

        ranked.sort(key=lambda item: (item[0], item[1], item[2].full_name))
        return [
            {
                "user_id": user.id,
                "full_name": user.full_name,
                "email": user.email,
                "phone_number": user.phone_number,
                "job_title": user.job_title,
                "comune": poi.comune if poi else None,
                "provincia": poi.provincia if poi else None,
                "regione": poi.regione if poi else None,
                "distance_km": round(distance_km, 1) if rank == 1 else None,
                "is_primary_zone": rank == 0,
            }
            for rank, distance_km, user, poi in ranked
        ]

    @staticmethod
    def _free_intervals(
        working_intervals: list[tuple[datetime, datetime]],
        busy_intervals: list[tuple[datetime, datetime]],
    ) -> list[tuple[datetime, datetime]]:
        if not working_intervals:
            return []
        busy = sorted(busy_intervals, key=lambda item: item[0])
        free_slots: list[tuple[datetime, datetime]] = []
        for start_at, end_at in working_intervals:
            cursor = start_at
            for busy_start, busy_end in busy:
                if busy_end <= cursor or busy_start >= end_at:
                    continue
                if busy_start > cursor:
                    free_slots.append((cursor, min(busy_start, end_at)))
                cursor = max(cursor, busy_end)
                if cursor >= end_at:
                    break
            if cursor < end_at:
                free_slots.append((cursor, end_at))
        return [(start_at, end_at) for start_at, end_at in free_slots if end_at > start_at]

    @staticmethod
    def _distance_from_origin(
        origin_lat: Optional[float],
        origin_lon: Optional[float],
        destination_lat: Optional[float],
        destination_lon: Optional[float],
    ) -> float:
        if None in {origin_lat, origin_lon, destination_lat, destination_lon}:
            return 0.0
        return InspectionWorkflowService._haversine_km(origin_lat, origin_lon, destination_lat, destination_lon)

    @staticmethod
    def _last_provisional_stop(context: TechnicianContext) -> Optional[ProposedStop]:
        if not context.provisional_stops:
            return None
        return sorted(context.provisional_stops, key=lambda item: item.ends_at)[-1]

    @staticmethod
    def _outside_zone(
        claim_context: ClaimPlanningContext,
        technician: TechnicianContext,
        max_outside_zone_km: int,
    ) -> tuple[bool, float]:
        normalized_municipality = InspectionWorkflowService._normalize_text(claim_context.municipality)
        if normalized_municipality and normalized_municipality in technician.assigned_municipalities:
            return False, 0.0

        if None not in {claim_context.latitude, claim_context.longitude, technician.latitude, technician.longitude}:
            distance_km = InspectionWorkflowService._haversine_km(
                technician.latitude,
                technician.longitude,
                claim_context.latitude,
                claim_context.longitude,
            )
            return distance_km > max_outside_zone_km, distance_km

        return True, float(max_outside_zone_km + 1)

    @staticmethod
    def _find_best_slot(
        claim_context: ClaimPlanningContext,
        technician: TechnicianContext,
        max_outside_zone_km: int,
        travel_matrix: Optional[dict[tuple[str, str, int, int], TravelEstimate]] = None,
        cat_stats_map: Optional[dict[tuple[str, int], int]] = None,
    ) -> Optional[tuple[ProposedStop, float]]:
        working_intervals = list(getattr(technician, "working_intervals", []))
        if not working_intervals:
            return None

        busy_intervals = list(technician.busy_intervals) + [
            (stop.starts_at, stop.ends_at) for stop in technician.provisional_stops
        ]
        free_intervals = InspectionWorkflowService._free_intervals(working_intervals, busy_intervals)
        if not free_intervals:
            return None

        forbidden_outside_zone, outside_distance = InspectionWorkflowService._outside_zone(
            claim_context,
            technician,
            max_outside_zone_km,
        )
        if forbidden_outside_zone:
            return None

        asset_count = InspectionWorkflowService._asset_count_for_claim(claim_context.claim)
        duration_minutes = InspectionWorkflowService._resolve_inspection_duration_minutes(
            asset_count,
            cat_stats_map=cat_stats_map,
            cat_user_id=technician.user_id,
        )

        best: Optional[tuple[ProposedStop, float]] = None
        last_stop = InspectionWorkflowService._last_provisional_stop(technician)
        for window in claim_context.preferred_windows:
            for free_start, free_end in free_intervals:
                # Hard constraint: l'intervento deve cadere dentro la finestra
                # scelta dall'assicurato (eventualmente già fusa con quelle contigue).
                interval_start = max(free_start, window["preferred_start"])
                interval_end = min(free_end, window["preferred_end"])
                if interval_end <= interval_start:
                    continue

                origin_lat = technician.latitude
                origin_lon = technician.longitude
                if last_stop and last_stop.ends_at <= interval_end:
                    origin_lat = last_stop.latitude if last_stop.latitude is not None else technician.latitude
                    origin_lon = last_stop.longitude if last_stop.longitude is not None else technician.longitude

                distance_from_previous = InspectionWorkflowService._distance_from_origin(
                    origin_lat,
                    origin_lon,
                    claim_context.latitude,
                    claim_context.longitude,
                )
                travel_minutes = InspectionWorkflowService._travel_minutes_for_leg(
                    origin_lat,
                    origin_lon,
                    claim_context.latitude,
                    claim_context.longitude,
                    departure=interval_start,
                    travel_matrix=travel_matrix,
                    fallback_distance_km=distance_from_previous,
                )
                earliest_start = interval_start
                if last_stop is not None:
                    earliest_start = max(earliest_start, last_stop.ends_at + timedelta(minutes=travel_minutes))

                proposed_end = earliest_start + timedelta(minutes=duration_minutes)
                if proposed_end > interval_end:
                    continue

                score = abs((earliest_start - window["preferred_start"]).total_seconds() / 60.0)
                score += distance_from_previous * 2.0
                score += outside_distance * 1.5
                if not technician.has_configured_poi:
                    score += 45.0

                stop = ProposedStop(
                    claim_id=claim_context.claim.id,
                    claim_reference=claim_context.reference,
                    starts_at=earliest_start,
                    ends_at=proposed_end,
                    municipality=claim_context.municipality,
                    province=claim_context.province,
                    region=claim_context.region,
                    masked_location=InspectionWorkflowService._masked_location(
                        claim_context.municipality,
                        claim_context.province,
                        claim_context.region,
                    ),
                    latitude=claim_context.latitude,
                    longitude=claim_context.longitude,
                    outside_zone=outside_distance > 0 and InspectionWorkflowService._normalize_text(claim_context.municipality) not in technician.assigned_municipalities,
                    distance_from_previous_km=round(distance_from_previous, 1),
                    duration_minutes=duration_minutes,
                    preferred_start=window["preferred_start"],
                )
                if best is None or score < best[1]:
                    best = (stop, score)
        return best

    @staticmethod
    def _travel_minutes_for_leg(
        origin_lat: Optional[float],
        origin_lon: Optional[float],
        dest_lat: Optional[float],
        dest_lon: Optional[float],
        *,
        departure: datetime,
        travel_matrix: Optional[dict[tuple[str, str, int, int], TravelEstimate]],
        fallback_distance_km: float,
    ) -> int:
        if (
            travel_matrix is not None
            and origin_lat is not None
            and origin_lon is not None
            and dest_lat is not None
            and dest_lon is not None
        ):
            origin = Coordinate(origin_lat, origin_lon)
            dest = Coordinate(dest_lat, dest_lon)
            key = (
                origin.grid(),
                dest.grid(),
                departure.weekday(),
                (departure.hour // 6) * 6,
            )
            hit = travel_matrix.get(key)
            if hit is not None:
                return hit.minutes
        return InspectionWorkflowService._estimate_travel_minutes(fallback_distance_km)

    @staticmethod
    async def _portal_day_slots(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        cat_settings: TenantCATSettingsPayload,
        location: dict,
        plan_date: date,
        slot_minutes: int,
    ) -> list[dict]:
        technicians = await InspectionWorkflowService._load_technician_contexts(
            db,
            tenant_id,
            cat_settings,
            plan_date,
        )
        if not technicians:
            return []

        claim_context = InspectionWorkflowService._build_location_claim_context(
            claim,
            location,
            slot_minutes,
        )
        candidates = InspectionWorkflowService._candidate_technicians_for_claim(
            claim_context,
            technicians,
            cat_settings.planner.max_outside_zone_kilometers,
        )
        if not candidates:
            return []

        now_utc = datetime.now(timezone.utc)
        now_local_date = now_utc.astimezone(LOCAL_TIMEZONE).date()
        slot_duration = timedelta(minutes=slot_minutes)
        aggregated: dict[str, dict] = {}

        for technician in candidates:
            working_intervals = list(getattr(technician, "working_intervals", []))
            if not working_intervals:
                continue
            free_intervals = InspectionWorkflowService._free_intervals(
                working_intervals,
                list(technician.busy_intervals),
            )
            for free_start, free_end in free_intervals:
                cursor = free_start
                if plan_date == now_local_date and cursor < now_utc:
                    cursor = now_utc
                while cursor + slot_duration <= free_end:
                    slot_start = cursor
                    slot_end = slot_start + slot_duration
                    if slot_start <= now_utc:
                        cursor = slot_end
                        continue
                    slot_id = slot_start.isoformat()
                    entry = aggregated.setdefault(
                        slot_id,
                        {
                            "id": slot_id,
                            "date": plan_date.isoformat(),
                            "start_at": slot_start,
                            "end_at": slot_end,
                            "label": f"{slot_start.astimezone(LOCAL_TIMEZONE).strftime('%H:%M')} - {slot_end.astimezone(LOCAL_TIMEZONE).strftime('%H:%M')}",
                            "available_cat_count": 0,
                            "candidate_user_ids": [],
                        },
                    )
                    if technician.user_id not in entry["candidate_user_ids"]:
                        entry["candidate_user_ids"].append(technician.user_id)
                        entry["available_cat_count"] += 1
                    cursor = slot_end

        return sorted(aggregated.values(), key=lambda item: item["start_at"])

    @staticmethod
    async def get_portal_scheduling_overview(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        horizon_days: int = 14,
    ) -> dict:
        claim = await InspectionWorkflowService._get_claim_or_raise(db, tenant_id, claim_id)
        _, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant_id)
        preferences = InspectionWorkflowService._preferences_metadata(claim)
        assignment = InspectionWorkflowService._assignment_metadata(claim)
        automation = InspectionWorkflowService._automation_metadata(claim)
        location = InspectionWorkflowService._location_defaults_for_claim(claim, cat_settings)
        selected_slots = InspectionWorkflowService._selected_slot_payload(preferences)

        enabled = claim.stato_corrente in CAT_ACTIVE_STATES or bool(selected_slots) or bool(location.get("confirmed_at"))
        if not enabled:
            return {
                "enabled": False,
                "status": "disabled",
                "workflow_stage": (claim.metadata_json or {}).get("inspection_workflow_stage"),
                "instructions": "La schedulazione sopralluogo non e attualmente richiesta.",
                "pending_confirmation_message": None,
                "address_confirmed": bool(location.get("confirmed_at")),
                "location": location,
                "selected_slots": selected_slots,
                "availability_days": [],
                "candidate_cats": [],
                "route_review_deadline": None,
                "route_proposal_event_id": None,
            }

        status_value = "selection_required"
        is_sopralluogo = claim.stato_corrente == ClaimStatus.SOPRALLUOGO.value
        if is_sopralluogo and (has_substato(claim, "fissato") or has_substato(claim, "confermato")):
            status_value = "confirmed"
        elif selected_slots:
            status_value = "pending_confirmation"
        elif is_sopralluogo and has_substato(claim, "da_concordare"):
            status_value = "manual_coordination"

        candidate_cats = await InspectionWorkflowService._candidate_cat_contacts_for_location(
            db,
            tenant_id,
            cat_settings,
            location,
        )

        availability_days: list[dict] = []
        if is_sopralluogo and (has_substato(claim, "da_fissare") or has_substato(claim, "da_concordare")):
            start_date = datetime.now(LOCAL_TIMEZONE).date()
            slot_minutes = max(60, int(cat_settings.planner.availability_slot_minutes or 120))
            for offset in range(horizon_days):
                plan_date = start_date + timedelta(days=offset)
                day_slots = await InspectionWorkflowService._portal_day_slots(
                    db,
                    tenant_id,
                    claim,
                    cat_settings,
                    location,
                    plan_date,
                    slot_minutes,
                )
                availability_days.append(
                    {
                        "date": plan_date.isoformat(),
                        "weekday_label": plan_date.strftime("%A"),
                        "is_available": bool(day_slots),
                        "slot_count": len(day_slots),
                        "slots": day_slots,
                    }
                )

        instructions = (
            "Conferma l'indirizzo del sopralluogo, posiziona il pin nel punto di incontro con il tecnico "
            "e seleziona una o piu fasce da due ore tra quelle disponibili per i CAT della tua zona."
        )
        if status_value == "pending_confirmation":
            instructions = (
                "Le tue preferenze sono state registrate e inoltrate al sistema appuntamenti. "
                "L'appuntamento non e ancora confermato."
            )
        elif status_value == "confirmed":
            instructions = "Il sopralluogo risulta gia fissato. Qui restano visibili posizione e storico preferenze."

        return {
            "enabled": True,
            "status": status_value,
            "workflow_stage": (claim.metadata_json or {}).get("inspection_workflow_stage"),
            "instructions": instructions,
            "pending_confirmation_message": (
                "Riceverai un messaggio di conferma del sopralluogo entro le 24 ore precedenti alla data selezionata. "
                "Fino a quel messaggio l'appuntamento non e confermato."
                if selected_slots and is_sopralluogo and (has_substato(claim, "da_fissare") or has_substato(claim, "da_concordare"))
                else None
            ),
            "address_confirmed": bool(location.get("confirmed_at")),
            "location": location,
            "selected_slots": selected_slots,
            "availability_days": availability_days,
            "candidate_cats": candidate_cats,
            "route_review_deadline": InspectionWorkflowService._parse_datetime(automation.get("review_deadline")),
            "route_proposal_event_id": assignment.get("route_proposal_event_id"),
        }

    @staticmethod
    async def _transition_claim(
        db: AsyncSession,
        claim: Claim,
        to_state: str,
        *,
        reason: Optional[str] = None,
        payload: Optional[dict] = None,
        sopralluogo_substato: Optional[str] = None,
    ) -> None:
        if claim.stato_corrente == to_state and not sopralluogo_substato:
            return
        # Same-state sopralluogo substato change: skip the state-machine and
        # update the substato directly.
        if claim.stato_corrente == to_state == ClaimStatus.SOPRALLUOGO.value and sopralluogo_substato:
            await StateService.set_substati(
                db,
                claim.tenant_id,
                claim.id,
                [sopralluogo_substato],
                source="system",
                commit=False,
            )
            return
        ok = await StateService.transition_state(
            db,
            claim.tenant_id,
            claim.id,
            claim.stato_corrente,
            to_state,
            None,
            reason=reason,
            payload=payload,
            commit=False,
            event_source="system",
            sopralluogo_substato=sopralluogo_substato,
        )
        if not ok:
            raise ValueError(f"Invalid transition {claim.stato_corrente} -> {to_state}")

    @staticmethod
    async def upsert_scheduling_preferences(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        payload: InspectionSchedulingPreferencesUpsert,
    ) -> Claim:
        claim = await InspectionWorkflowService._get_claim_or_raise(db, tenant_id, claim_id)
        now = datetime.now(timezone.utc)
        confirmed_at = payload.confirmed_at or now

        metadata = InspectionWorkflowService._metadata(claim)
        metadata["inspection_preferences"] = {
            "address_line": payload.address_line,
            "municipality": payload.municipality,
            "province": payload.province,
            "region": payload.region,
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "confirmed_at": confirmed_at.astimezone(timezone.utc).isoformat(),
            "requested_duration_minutes": payload.requested_duration_minutes,
            "notes": payload.notes,
            "preferred_slots": [
                {
                    "date": slot.date.isoformat(),
                    "start_time": slot.start_time.isoformat(timespec="minutes"),
                    "end_time": slot.end_time.isoformat(timespec="minutes"),
                    "label": slot.label,
                }
                for slot in payload.preferred_slots
            ],
        }
        automation = dict(metadata.get("inspection_automation") or {})
        eligible_generation_dates = sorted(
            {
                (slot.date - timedelta(days=INSPECTION_LEAD_DAYS)).isoformat()
                for slot in payload.preferred_slots
            }
        )
        automation["eligible_route_generation_date"] = eligible_generation_dates[0] if eligible_generation_dates else None
        automation["last_preferences_confirmed_at"] = confirmed_at.astimezone(timezone.utc).isoformat()
        metadata["inspection_automation"] = automation
        InspectionWorkflowService._save_metadata(claim, metadata)
        await InspectionWorkflowService._upsert_preference_projection(
            db,
            tenant_id,
            claim,
            address_line=payload.address_line,
            municipality=payload.municipality,
            province=payload.province,
            region=payload.region,
            latitude=payload.latitude,
            longitude=payload.longitude,
            confirmed_at=confirmed_at.astimezone(timezone.utc),
            requested_duration_minutes=payload.requested_duration_minutes,
            notes=payload.notes,
            source="portal",
            preferred_slots=payload.preferred_slots,
        )

        if claim.stato_corrente in AUTO_ENTRY_STATES:
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                ClaimStatus.SOPRALLUOGO.value,
                reason="inspection_preferences_confirmed",
                sopralluogo_substato="da_fissare",
            )

        await InspectionWorkflowService._create_claim_event(
            db,
            tenant_id,
            claim.id,
            "inspection_preferences_confirmed",
            {
                "preferred_slots_count": len(payload.preferred_slots),
                "eligible_route_generation_date": automation.get("eligible_route_generation_date"),
            },
        )
        await db.commit()
        await db.refresh(claim)
        return claim

    @staticmethod
    async def upsert_portal_location(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        address_line: Optional[str],
        municipality: Optional[str],
        province: Optional[str],
        region: Optional[str],
        latitude: Optional[float],
        longitude: Optional[float],
    ) -> Claim:
        claim = await InspectionWorkflowService._get_claim_or_raise(db, tenant_id, claim_id)
        _, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant_id)
        current_location = InspectionWorkflowService._location_defaults_for_claim(claim, cat_settings)
        nearest = InspectionWorkflowService._nearest_municipality(cat_settings, latitude, longitude)

        now = datetime.now(timezone.utc)
        metadata = InspectionWorkflowService._metadata(claim)
        preferences = dict(metadata.get("inspection_preferences") or {})
        preferences.update(
            {
                "address_line": (address_line or current_location.get("address_line") or "").strip() or None,
                "municipality": (municipality or (nearest.comune if nearest else None) or current_location.get("municipality") or "").strip() or None,
                "province": (province or (nearest.provincia if nearest else None) or current_location.get("province") or "").strip() or None,
                "region": (region or (nearest.regione if nearest else None) or current_location.get("region") or "").strip() or None,
                "latitude": latitude if latitude is not None else current_location.get("latitude"),
                "longitude": longitude if longitude is not None else current_location.get("longitude"),
                "confirmed_at": now.isoformat(),
                "preferred_slots": list(preferences.get("preferred_slots") or []),
                "requested_duration_minutes": preferences.get("requested_duration_minutes"),
                "notes": preferences.get("notes"),
            }
        )
        metadata["inspection_preferences"] = preferences
        InspectionWorkflowService._save_metadata(claim, metadata)
        slot_payload = [
            InspectionPreferredSlotInput(
                date=InspectionWorkflowService._parse_date(slot.get("date")) or now.date(),
                start_time=InspectionWorkflowService._parse_time(slot.get("start_time")) or time(hour=9),
                end_time=InspectionWorkflowService._parse_time(slot.get("end_time")) or time(hour=11),
                label=slot.get("label"),
            )
            for slot in preferences.get("preferred_slots") or []
            if isinstance(slot, dict)
            and InspectionWorkflowService._parse_date(slot.get("date")) is not None
            and InspectionWorkflowService._parse_time(slot.get("start_time")) is not None
            and InspectionWorkflowService._parse_time(slot.get("end_time")) is not None
        ]
        await InspectionWorkflowService._upsert_preference_projection(
            db,
            tenant_id,
            claim,
            address_line=preferences.get("address_line"),
            municipality=preferences.get("municipality"),
            province=preferences.get("province"),
            region=preferences.get("region"),
            latitude=preferences.get("latitude"),
            longitude=preferences.get("longitude"),
            confirmed_at=now,
            requested_duration_minutes=preferences.get("requested_duration_minutes"),
            notes=preferences.get("notes"),
            source="portal",
            preferred_slots=slot_payload,
        )

        if claim.stato_corrente in AUTO_ENTRY_STATES:
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                ClaimStatus.SOPRALLUOGO.value,
                reason="inspection_location_confirmed",
                sopralluogo_substato="da_fissare",
            )

        await InspectionWorkflowService._create_claim_event(
            db,
            tenant_id,
            claim.id,
            "inspection_location_confirmed",
            {
                "address_line": preferences.get("address_line"),
                "municipality": preferences.get("municipality"),
                "province": preferences.get("province"),
                "region": preferences.get("region"),
            },
            source="portal",
        )
        await db.commit()
        await db.refresh(claim)
        return claim

    @staticmethod
    async def submit_portal_preferences(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        selected_slots: list[InspectionPreferredSlotInput],
        notes: Optional[str],
        requested_duration_minutes: Optional[int],
    ) -> Claim:
        claim = await InspectionWorkflowService._get_claim_or_raise(db, tenant_id, claim_id)
        _, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant_id)
        location = InspectionWorkflowService._location_defaults_for_claim(claim, cat_settings)
        if not location.get("address_line"):
            raise ValueError("Inspection address must be confirmed before choosing time slots")

        payload = InspectionSchedulingPreferencesUpsert(
            address_line=location.get("address_line"),
            municipality=location.get("municipality"),
            province=location.get("province"),
            region=location.get("region"),
            latitude=location.get("latitude"),
            longitude=location.get("longitude"),
            confirmed_at=location.get("confirmed_at") or datetime.now(timezone.utc),
            preferred_slots=selected_slots,
            requested_duration_minutes=requested_duration_minutes,
            notes=notes,
        )
        return await InspectionWorkflowService.upsert_scheduling_preferences(
            db,
            tenant_id,
            claim_id,
            payload,
        )

    @staticmethod
    async def create_manual_appointment(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        payload: InspectionManualAppointmentCreate,
    ) -> Claim:
        claim = await InspectionWorkflowService._get_claim_or_raise(db, tenant_id, claim_id)
        start_at = InspectionWorkflowService._parse_datetime(payload.scheduled_start)
        end_at = InspectionWorkflowService._parse_datetime(payload.scheduled_end)
        if not start_at or not end_at or end_at <= start_at:
            raise ValueError("Invalid manual appointment interval")

        cat_user: Optional[User] = None
        if payload.cat_user_id:
            result = await db.execute(
                select(User).where(
                    User.id == payload.cat_user_id,
                    User.tenant_id == tenant_id,
                    User.is_active == True,
                )
            )
            cat_user = result.scalar_one_or_none()
        elif payload.cat_email:
            result = await db.execute(
                select(User).where(
                    User.email == payload.cat_email.strip().lower(),
                    User.tenant_id == tenant_id,
                    User.is_active == True,
                )
            )
            cat_user = result.scalar_one_or_none()

        metadata = InspectionWorkflowService._metadata(claim)
        assignment = dict(metadata.get("inspection_assignment") or {})
        assignment.update(
            {
                "manual_fixed": True,
                "immutable": True,
                "scheduled_start": start_at.isoformat(),
                "scheduled_end": end_at.isoformat(),
                "assigned_cat_user_id": cat_user.id if cat_user else None,
                "assigned_cat_email": cat_user.email if cat_user else payload.cat_email,
                "note": payload.note,
            }
        )
        metadata["inspection_assignment"] = assignment
        automation = dict(metadata.get("inspection_automation") or {})
        automation["manual_fixed_at"] = datetime.now(timezone.utc).isoformat()
        metadata["inspection_automation"] = automation
        InspectionWorkflowService._save_metadata(claim, metadata)
        preference_payload, _ = await InspectionWorkflowService._load_preference_projection(db, claim.id)
        await InspectionWorkflowService._upsert_preference_projection(
            db,
            tenant_id,
            claim,
            address_line=(
                preference_payload.address_line
                if preference_payload and preference_payload.address_line
                else claim.indirizzo_assicurato
            ),
            municipality=preference_payload.municipality if preference_payload else None,
            province=preference_payload.province if preference_payload else None,
            region=preference_payload.region if preference_payload else None,
            latitude=float(preference_payload.latitude) if preference_payload and preference_payload.latitude is not None else None,
            longitude=float(preference_payload.longitude) if preference_payload and preference_payload.longitude is not None else None,
            confirmed_at=preference_payload.confirmed_at if preference_payload else None,
            requested_duration_minutes=preference_payload.requested_duration_minutes if preference_payload else None,
            notes=preference_payload.notes if preference_payload else payload.note,
            source="manual",
            preferred_slots=[],
        )

        if claim.stato_corrente != ClaimStatus.SOPRALLUOGO.value:
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                ClaimStatus.SOPRALLUOGO.value,
                reason="manual_inspection_appointment",
                sopralluogo_substato="da_concordare",
            )

        if cat_user:
            db.add(
                CalendarEvent(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    claim_id=claim.id,
                    owner_user_id=cat_user.id,
                    title=f"Sopralluogo {claim.external_ref or claim.numero_sinistro or claim.id}",
                    description=payload.note,
                    event_type=CONFIRMED_APPOINTMENT_EVENT_TYPE,
                    starts_at=start_at,
                    ends_at=end_at,
                    location=claim.indirizzo_assicurato,
                    status="confirmed",
                    visibility="tenant",
                    source="manual",
                    metadata_json={
                        "manual_fixed": True,
                        "claim_reference": claim.external_ref or claim.numero_sinistro or claim.id,
                    },
                )
            )

        await InspectionWorkflowService._transition_claim(
            db,
            claim,
            ClaimStatus.SOPRALLUOGO.value,
            reason="manual_inspection_appointment_confirmed",
            payload={"scheduled_at": start_at.isoformat()},
            sopralluogo_substato="fissato",
        )
        await InspectionWorkflowService._create_claim_event(
            db,
            tenant_id,
            claim.id,
            "inspection_manual_appointment_created",
            {
                "scheduled_start": start_at.isoformat(),
                "scheduled_end": end_at.isoformat(),
                "cat_user_id": cat_user.id if cat_user else None,
                "cat_email": cat_user.email if cat_user else payload.cat_email,
            },
        )
        await db.commit()
        await db.refresh(claim)
        return claim

    @staticmethod
    async def upsert_daily_availability_override(
        db: AsyncSession,
        tenant_id: str,
        owner_user_id: str,
        target_date: date,
        payload: InspectionAvailabilityOverrideUpsert,
    ) -> InspectionAvailabilityDayResponse:
        result = await db.execute(
            select(User).where(
                User.id == owner_user_id,
                User.tenant_id == tenant_id,
                User.is_active == True,
            )
        )
        user = result.scalar_one_or_none()
        if user is None:
            raise ValueError("CAT user not found")

        settings_json = InspectionWorkflowService._user_settings(user)
        overrides = InspectionWorkflowService._availability_overrides(user)
        overrides[target_date.isoformat()] = InspectionWorkflowService._serialize_availability_override(payload)
        settings_json["inspection_availability_overrides"] = overrides
        user.settings_json = settings_json or None
        await InspectionWorkflowService._upsert_availability_override_projection(
            db,
            tenant_id,
            owner_user_id,
            target_date,
            payload,
            source="cat_ipad",
        )
        await db.commit()

        month_response = await InspectionWorkflowService.list_monthly_availability(
            db,
            tenant_id,
            owner_user_id,
            date(target_date.year, target_date.month, 1),
        )
        for item in month_response.items:
            if item.date == target_date:
                return item
        raise ValueError("Failed to rebuild availability day")

    @staticmethod
    async def list_monthly_availability(
        db: AsyncSession,
        tenant_id: str,
        owner_user_id: str,
        month: date,
    ) -> InspectionAvailabilityMonthResponse:
        month_start = date(month.year, month.month, 1)
        if month.month == 12:
            next_month = date(month.year + 1, 1, 1)
        else:
            next_month = date(month.year, month.month + 1, 1)

        result = await db.execute(
            select(User).where(
                User.id == owner_user_id,
                User.tenant_id == tenant_id,
                User.is_active == True,
            )
        )
        user = result.scalar_one_or_none()
        if user is None:
            raise ValueError("CAT user not found")

        schedule_result = await db.execute(
            select(UserWorkSchedule).where(
                UserWorkSchedule.tenant_id == tenant_id,
                UserWorkSchedule.user_id == owner_user_id,
                or_(UserWorkSchedule.effective_from.is_(None), UserWorkSchedule.effective_from < next_month),
                or_(UserWorkSchedule.effective_to.is_(None), UserWorkSchedule.effective_to >= month_start),
            )
        )
        schedule_items = []
        for schedule in schedule_result.scalars().all():
            if schedule.location and InspectionWorkflowService._normalize_text(schedule.location) == "remote":
                continue
            metadata = schedule.metadata_json or {}
            if InspectionWorkflowService._normalize_text(str(metadata.get("place", ""))) == "remote":
                continue
            if schedule.end_time <= schedule.start_time:
                continue
            schedule_items.append(schedule)

        range_start = datetime.combine(month_start, time.min, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
        range_end = datetime.combine(next_month, time.min, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)
        events_result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.tenant_id == tenant_id,
                CalendarEvent.owner_user_id == owner_user_id,
                CalendarEvent.starts_at < range_end,
                CalendarEvent.ends_at > range_start,
                CalendarEvent.status.in_(["confirmed", "proposed", "accepted"]),
            )
        )
        events = events_result.scalars().all()
        events_by_date: dict[date, list[InspectionAvailabilityCommitmentResponse]] = {}
        has_confirmed_route_dates: set[date] = set()
        for event in events:
            local_start = event.starts_at.astimezone(LOCAL_TIMEZONE)
            local_end = event.ends_at.astimezone(LOCAL_TIMEZONE)
            event_date = local_start.date()
            if not (month_start <= event_date < next_month):
                continue
            metadata = dict(event.metadata_json or {})
            if event.event_type == ROUTE_PROPOSAL_EVENT_TYPE and event.status == "accepted":
                has_confirmed_route_dates.add(event_date)
            if event.event_type == CONFIRMED_APPOINTMENT_EVENT_TYPE:
                has_confirmed_route_dates.add(event_date)
            if event.event_type == ROUTE_PROPOSAL_EVENT_TYPE and event.status not in {"accepted"}:
                continue
            events_by_date.setdefault(event_date, []).append(
                InspectionAvailabilityCommitmentResponse(
                    id=event.id,
                    tenant_name=metadata.get("tenant_name") or "Tenant corrente",
                    label=event.title,
                    start_time=local_start.timetz().replace(tzinfo=None),
                    end_time=local_end.timetz().replace(tzinfo=None),
                )
            )

        override_records = await InspectionWorkflowService._load_availability_override_projection_map(
            db,
            tenant_id,
            owner_user_id,
            month_start,
            next_month,
        )
        overrides = InspectionWorkflowService._availability_overrides(user)
        items: list[InspectionAvailabilityDayResponse] = []
        cursor = month_start
        while cursor < next_month:
            projection_override = override_records.get(cursor)
            date_key = cursor.isoformat()
            legacy_override = overrides.get(date_key) if isinstance(overrides.get(date_key), dict) else None
            if projection_override is not None:
                override_row, override_windows = projection_override
                windows = [
                    InspectionAvailabilityWindowInput(
                        start_time=window.start_time,
                        end_time=window.end_time,
                    )
                    for window in override_windows
                    if window.end_time > window.start_time
                ]
                is_available = bool(override_row.is_available)
                note = override_row.note
                source = "override"
            elif legacy_override is not None:
                windows = [
                    InspectionAvailabilityWindowInput(start_time=start_time, end_time=end_time)
                    for start_time, end_time in InspectionWorkflowService._availability_windows_from_override(legacy_override)
                ]
                is_available = bool(legacy_override.get("is_available"))
                note = legacy_override.get("note")
                source = "override"
            else:
                day_windows: list[InspectionAvailabilityWindowInput] = []
                weekday_candidates = InspectionWorkflowService._weekday_candidates(cursor)
                for schedule in schedule_items:
                    if schedule.weekday not in weekday_candidates:
                        continue
                    if schedule.effective_from and schedule.effective_from > cursor:
                        continue
                    if schedule.effective_to and schedule.effective_to < cursor:
                        continue
                    candidate = InspectionAvailabilityWindowInput(
                        start_time=schedule.start_time,
                        end_time=schedule.end_time,
                    )
                    if candidate not in day_windows:
                        day_windows.append(candidate)
                windows = sorted(day_windows, key=lambda item: item.start_time)
                is_available = len(windows) > 0
                note = None
                source = "recurring"

            items.append(
                InspectionAvailabilityDayResponse(
                    date=cursor,
                    is_available=is_available,
                    note=note,
                    windows=windows,
                    external_commitments=events_by_date.get(cursor, []),
                    has_confirmed_route=cursor in has_confirmed_route_dates,
                    source=source,
                )
            )
            cursor += timedelta(days=1)

        return InspectionAvailabilityMonthResponse(
            owner_user_id=owner_user_id,
            month=month_start,
            items=items,
        )

    @staticmethod
    async def _eligible_claim_contexts(
        db: AsyncSession,
        tenant_id: str,
        plan_date: date,
        tolerance_percent: int,
        *,
        claim_ids: Optional[set[str]] = None,
        skip_claim_ids: Optional[set[str]] = None,
    ) -> list[ClaimPlanningContext]:
        query = select(Claim).where(
            Claim.tenant_id == tenant_id,
            Claim.stato_corrente == ClaimStatus.SOPRALLUOGO.value,
            Claim.stato_substati.contains([{"tag": "da_fissare"}]),
            Claim.sopralluogo == True,
        )
        if claim_ids:
            query = query.where(Claim.id.in_(claim_ids))
        result = await db.execute(query)
        contexts: list[ClaimPlanningContext] = []
        for claim in result.scalars().all():
            if skip_claim_ids and claim.id in skip_claim_ids:
                continue
            preferences = InspectionWorkflowService._preferences_metadata(claim)
            if not preferences.get("confirmed_at"):
                continue
            assignment = InspectionWorkflowService._assignment_metadata(claim)
            if assignment.get("manual_fixed"):
                continue
            claim_context = InspectionWorkflowService._build_claim_context(claim, plan_date, tolerance_percent)
            if claim_context is not None:
                contexts.append(claim_context)
        return sorted(
            contexts,
            key=lambda item: item.preferred_windows[0]["preferred_start"],
        )

    @staticmethod
    async def _active_route_claim_ids_for_plan_date(
        db: AsyncSession,
        tenant_id: str,
        plan_date: date,
    ) -> set[str]:
        proposal_result = await db.execute(
            select(InspectionRouteProposal.id).where(
                InspectionRouteProposal.tenant_id == tenant_id,
                InspectionRouteProposal.plan_date == plan_date,
                InspectionRouteProposal.status.in_(["proposed", "accepted"]),
            )
        )
        proposal_ids = [row[0] for row in proposal_result.all()]
        if proposal_ids:
            stops_result = await db.execute(
                select(InspectionRouteStop.claim_id).where(InspectionRouteStop.proposal_id.in_(proposal_ids))
            )
            claim_ids = {row[0] for row in stops_result.all() if isinstance(row[0], str)}
            if claim_ids:
                return claim_ids

        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.tenant_id == tenant_id,
                CalendarEvent.event_type == ROUTE_PROPOSAL_EVENT_TYPE,
                CalendarEvent.status.in_(["proposed", "accepted"]),
            )
        )
        claim_ids: set[str] = set()
        for event in result.scalars().all():
            metadata = InspectionWorkflowService._route_metadata(event)
            if metadata.get("plan_date") != plan_date.isoformat():
                continue
            for claim_id in metadata.get("claim_ids", []):
                if isinstance(claim_id, str):
                    claim_ids.add(claim_id)
        return claim_ids

    @staticmethod
    async def _supersede_proposed_routes_for_plan_date(
        db: AsyncSession,
        tenant_id: str,
        plan_date: date,
    ) -> None:
        proposals = await InspectionWorkflowService._list_route_projection_records(
            db,
            tenant_id,
            status_filter="proposed",
            plan_date=plan_date,
        )
        for proposal in proposals:
            metadata = InspectionWorkflowService._route_projection_metadata(proposal)
            metadata["route_status"] = "superseded"
            metadata["superseded_at"] = datetime.now(timezone.utc).isoformat()
            proposal.status = "superseded"
            proposal.metadata_json = metadata

        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.tenant_id == tenant_id,
                CalendarEvent.event_type == ROUTE_PROPOSAL_EVENT_TYPE,
                CalendarEvent.status == "proposed",
            )
        )
        for event in result.scalars().all():
            metadata = InspectionWorkflowService._route_metadata(event)
            if metadata.get("plan_date") != plan_date.isoformat():
                continue
            event.status = "superseded"
            metadata["route_status"] = "superseded"
            metadata["superseded_at"] = datetime.now(timezone.utc).isoformat()
            event.metadata_json = metadata

    @staticmethod
    def _candidate_technicians_for_claim(
        claim_context: ClaimPlanningContext,
        technicians: list[TechnicianContext],
        max_outside_zone_km: int,
    ) -> list[TechnicianContext]:
        normalized_municipality = InspectionWorkflowService._normalize_text(claim_context.municipality)
        primary: list[TechnicianContext] = []
        secondary: list[tuple[float, TechnicianContext]] = []
        fallback: list[TechnicianContext] = []
        for technician in technicians:
            if normalized_municipality and normalized_municipality in technician.assigned_municipalities:
                primary.append(technician)
                continue
            if None not in {claim_context.latitude, claim_context.longitude, technician.latitude, technician.longitude}:
                distance_km = InspectionWorkflowService._haversine_km(
                    technician.latitude,
                    technician.longitude,
                    claim_context.latitude,
                    claim_context.longitude,
                )
                if distance_km <= max_outside_zone_km:
                    secondary.append((distance_km, technician))
                    continue
            fallback.append(technician)
        if primary:
            return primary + [item[1] for item in sorted(secondary, key=lambda entry: entry[0])]
        if secondary:
            return [item[1] for item in sorted(secondary, key=lambda entry: entry[0])]
        return fallback

    @staticmethod
    def _provider_settings_for_tenant(tenant: Tenant) -> dict:
        raw = (tenant.settings_json or {}).get("provider_settings") or {}
        return raw if isinstance(raw, dict) else {}

    @staticmethod
    async def _prefetch_travel_matrix(
        db: AsyncSession,
        tenant: Tenant,
        plan_date: date,
        technicians: list[TechnicianContext],
        claim_contexts: list[ClaimPlanningContext],
    ) -> dict[tuple[str, str, int, int], TravelEstimate]:
        provider_settings = InspectionWorkflowService._provider_settings_for_tenant(tenant)
        service = TravelTimeService(
            db,
            api_key=provider_settings.get("routing_api_key"),
            cache_ttl_days=int(provider_settings.get("routing_cache_ttl_days") or 14),
            enabled=bool(provider_settings.get("routing_enabled")),
        )
        departure_default = datetime.combine(
            plan_date, time(9, 0), tzinfo=LOCAL_TIMEZONE
        ).astimezone(timezone.utc)

        claim_coords: list[Coordinate] = []
        for ctx in claim_contexts:
            if ctx.latitude is not None and ctx.longitude is not None:
                claim_coords.append(Coordinate(float(ctx.latitude), float(ctx.longitude)))

        pairs: list[tuple[Coordinate, Coordinate, datetime]] = []
        for tech in technicians:
            if tech.latitude is None or tech.longitude is None:
                continue
            origin = Coordinate(float(tech.latitude), float(tech.longitude))
            for dest in claim_coords:
                pairs.append((origin, dest, departure_default))
        # chained stops (claim_i -> claim_j) sono opzionali ma il cache li
        # accumula sui run successivi; per non sforare i limiti API ci limitiamo
        # qui a tech -> claim e lasciamo i salti tra claim alla risoluzione
        # singola (che usa comunque cache + fallback haversine).

        if not pairs:
            return {}
        return await service.estimate_matrix(pairs)

    @staticmethod
    async def _load_cat_stats_map(
        db: AsyncSession,
        tenant_id: str,
        technicians: list[TechnicianContext],
        claim_contexts: list[ClaimPlanningContext],
    ) -> dict[tuple[str, int], int]:
        buckets = {
            bucket_for_asset_count(
                InspectionWorkflowService._asset_count_for_claim(ctx.claim)
            )
            for ctx in claim_contexts
        }
        if not buckets or not technicians:
            return {}
        result: dict[tuple[str, int], int] = {}
        for tech in technicians:
            for bucket in buckets:
                stat = await load_median_minutes(db, tenant_id, tech.user_id, bucket)
                if stat is not None:
                    result[(tech.user_id, bucket)] = stat.median_minutes
        return result

    @staticmethod
    async def _build_route_proposals(
        db: AsyncSession,
        tenant_id: str,
        plan_date: date,
        *,
        claim_ids: Optional[set[str]] = None,
        excluded_user_ids: Optional[set[str]] = None,
        force: bool = False,
    ) -> dict:
        tenant, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant_id)
        if not cat_settings.enabled:
            return {
                "generated_routes_count": 0,
                "claims_planned": 0,
                "claims_fallback_manual": 0,
                "skipped_claims": 0,
                "route_event_ids": [],
                "fallback_claim_ids": [],
            }

        if force:
            await InspectionWorkflowService._supersede_proposed_routes_for_plan_date(db, tenant_id, plan_date)
            active_claim_ids: set[str] = set()
        else:
            active_claim_ids = await InspectionWorkflowService._active_route_claim_ids_for_plan_date(db, tenant_id, plan_date)

        claim_contexts = await InspectionWorkflowService._eligible_claim_contexts(
            db,
            tenant_id,
            plan_date,
            cat_settings.planner.availability_tolerance_percent,
            claim_ids=claim_ids,
            skip_claim_ids=active_claim_ids if not force else None,
        )
        if not claim_contexts:
            return {
                "generated_routes_count": 0,
                "claims_planned": 0,
                "claims_fallback_manual": 0,
                "skipped_claims": len(active_claim_ids) if not force else 0,
                "route_event_ids": [],
                "fallback_claim_ids": [],
            }

        technicians = await InspectionWorkflowService._load_technician_contexts(
            db,
            tenant_id,
            cat_settings,
            plan_date,
        )
        if excluded_user_ids:
            technicians = [technician for technician in technicians if technician.user_id not in excluded_user_ids]
        if not technicians:
            fallback_claim_ids = [context.claim.id for context in claim_contexts]
            return {
                "generated_routes_count": 0,
                "claims_planned": 0,
                "claims_fallback_manual": len(fallback_claim_ids),
                "skipped_claims": len(active_claim_ids) if not force else 0,
                "route_event_ids": [],
                "fallback_claim_ids": fallback_claim_ids,
            }

        travel_matrix = await InspectionWorkflowService._prefetch_travel_matrix(
            db,
            tenant,
            plan_date,
            technicians,
            claim_contexts,
        )
        cat_stats_map = await InspectionWorkflowService._load_cat_stats_map(
            db,
            tenant_id,
            technicians,
            claim_contexts,
        )

        fallback_claim_ids: list[str] = []
        for claim_context in claim_contexts:
            candidates = InspectionWorkflowService._candidate_technicians_for_claim(
                claim_context,
                technicians,
                cat_settings.planner.max_outside_zone_kilometers,
            )
            best_choice: Optional[tuple[TechnicianContext, ProposedStop, float]] = None
            for technician in candidates:
                choice = InspectionWorkflowService._find_best_slot(
                    claim_context,
                    technician,
                    cat_settings.planner.max_outside_zone_kilometers,
                    travel_matrix=travel_matrix,
                    cat_stats_map=cat_stats_map,
                )
                if choice is None:
                    continue
                stop, score = choice
                if best_choice is None or score < best_choice[2]:
                    best_choice = (technician, stop, score)

            if best_choice is None:
                fallback_claim_ids.append(claim_context.claim.id)
                continue

            technician, stop, _ = best_choice
            technician.provisional_stops.append(stop)

        now = datetime.now(timezone.utc)
        claim_context_by_id = {context.claim.id: context for context in claim_contexts}
        route_event_ids: list[str] = []
        claims_planned = 0
        for technician in technicians:
            stops = sorted(technician.provisional_stops, key=lambda item: item.starts_at)
            if not stops:
                continue
            total_duration_minutes = int(sum(stop.duration_minutes for stop in stops))
            total_distance_km = round(sum(stop.distance_from_previous_km for stop in stops), 1)
            review_deadline = now + timedelta(minutes=cat_settings.planner.route_review_window_minutes)
            route_id = str(uuid.uuid4())
            stop_payloads = [
                {
                    "claim_id": stop.claim_id,
                    "claim_reference": stop.claim_reference,
                    "starts_at": stop.starts_at.isoformat(),
                    "ends_at": stop.ends_at.isoformat(),
                    "municipality": stop.municipality,
                    "province": stop.province,
                    "region": stop.region,
                    "latitude": stop.latitude,
                    "longitude": stop.longitude,
                    "masked_location": stop.masked_location,
                    "outside_zone": stop.outside_zone,
                    "distance_from_previous_km": stop.distance_from_previous_km,
                    "duration_minutes": stop.duration_minutes,
                    "asset_count": max(
                        int(
                            (
                                InspectionWorkflowService._metadata(
                                    claim_context_by_id[stop.claim_id].claim
                                ).get("numero_beni")
                                or 1
                            )
                        ),
                        1,
                    )
                    if str(
                        InspectionWorkflowService._metadata(
                            claim_context_by_id[stop.claim_id].claim
                        ).get("numero_beni")
                        or "1"
                    ).isdigit()
                    else 1,
                    "complexity": (claim_context_by_id[stop.claim_id].claim.complessita or "").lower() or None,
                    "manually_fixed": False,
                    "note": InspectionWorkflowService._preferences_metadata(
                        claim_context_by_id[stop.claim_id].claim
                    ).get("notes"),
                    "preferred_windows": [
                        {
                            "start_time": window["preferred_start"].astimezone(LOCAL_TIMEZONE).time().isoformat(timespec="minutes"),
                            "end_time": window["preferred_end"].astimezone(LOCAL_TIMEZONE).time().isoformat(timespec="minutes"),
                            "label": window.get("label"),
                        }
                        for window in claim_context_by_id[stop.claim_id].preferred_windows
                    ],
                }
                for stop in stops
            ]
            route_metadata = {
                "route_status": "proposed",
                "plan_date": plan_date.isoformat(),
                "review_deadline": review_deadline.isoformat(),
                "claim_ids": [stop.claim_id for stop in stops],
                "generated_at": now.isoformat(),
                "generated_by": "inspection_automation",
                "tenant_names": [tenant.name],
                "owner_email": technician.email,
                "owner_name": technician.full_name,
                "has_configured_poi": technician.has_configured_poi,
                "total_distance_km": total_distance_km,
                "total_duration_minutes": total_duration_minutes,
                "stops": stop_payloads,
                "rejection_history": [],
            }
            event = CalendarEvent(
                id=route_id,
                tenant_id=tenant_id,
                claim_id=None,
                owner_user_id=technician.user_id,
                title=f"Route CAT {plan_date.isoformat()} · {technician.full_name}",
                description="Proposta automatica di sopralluoghi",
                event_type=ROUTE_PROPOSAL_EVENT_TYPE,
                starts_at=stops[0].starts_at,
                ends_at=stops[-1].ends_at,
                all_day=False,
                location=technician.comune or None,
                status="proposed",
                visibility="tenant",
                source="inspection_automation",
                metadata_json=route_metadata,
            )
            db.add(event)
            await InspectionWorkflowService._sync_route_projection(
                db,
                proposal_id=route_id,
                tenant_id=tenant_id,
                owner_user_id=technician.user_id,
                title=event.title,
                description=event.description,
                plan_date=plan_date,
                status="proposed",
                generated_at=now,
                review_deadline=review_deadline,
                source=event.source,
                has_configured_poi=technician.has_configured_poi,
                total_distance_km=total_distance_km,
                total_duration_minutes=total_duration_minutes,
                tenant_names=[tenant.name],
                metadata=route_metadata,
                stops=stop_payloads,
            )
            route_event_ids.append(event.id)
            claims_planned += len(stops)

            for stop in stops:
                claim = next(context.claim for context in claim_contexts if context.claim.id == stop.claim_id)
                metadata = InspectionWorkflowService._metadata(claim)
                assignment = dict(metadata.get("inspection_assignment") or {})
                assignment.update(
                    {
                        "route_proposal_event_id": event.id,
                        "assigned_cat_user_id": technician.user_id,
                        "assigned_cat_email": technician.email,
                        "assigned_cat_name": technician.full_name,
                        "planned_slot_start": stop.starts_at.isoformat(),
                        "planned_slot_end": stop.ends_at.isoformat(),
                        "outside_zone": stop.outside_zone,
                        "masked_location": stop.masked_location,
                    }
                )
                metadata["inspection_assignment"] = assignment
                automation = dict(metadata.get("inspection_automation") or {})
                automation.update(
                    {
                        "route_plan_date": plan_date.isoformat(),
                        "last_route_generated_at": now.isoformat(),
                        "review_deadline": review_deadline.isoformat(),
                    }
                )
                metadata["inspection_automation"] = automation
                InspectionWorkflowService._save_metadata(claim, metadata)
                await InspectionWorkflowService._create_claim_event(
                    db,
                    tenant_id,
                    claim.id,
                    "inspection_route_proposed",
                    {
                        "route_event_id": event.id,
                        "assigned_cat_user_id": technician.user_id,
                        "plan_date": plan_date.isoformat(),
                        "scheduled_start": stop.starts_at.isoformat(),
                    },
                )

        for fallback_claim_id in fallback_claim_ids:
            claim = next(context.claim for context in claim_contexts if context.claim.id == fallback_claim_id)
            metadata = InspectionWorkflowService._metadata(claim)
            assignment = dict(metadata.get("inspection_assignment") or {})
            assignment.update(
                {
                    "route_proposal_event_id": None,
                    "assigned_cat_user_id": None,
                    "assigned_cat_email": None,
                    "assigned_cat_name": None,
                    "planned_slot_start": None,
                    "planned_slot_end": None,
                    "outside_zone": None,
                }
            )
            metadata["inspection_assignment"] = assignment
            automation = dict(metadata.get("inspection_automation") or {})
            automation.update(
                {
                    "route_plan_date": plan_date.isoformat(),
                    "last_route_generated_at": now.isoformat(),
                    "last_rejection_code": "no_available_cat",
                    "last_rejection_reason": "Nessun CAT disponibile per la finestra richiesta",
                }
            )
            metadata["inspection_automation"] = automation
            InspectionWorkflowService._save_metadata(claim, metadata)
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                ClaimStatus.SOPRALLUOGO.value,
                reason="inspection_auto_planning_failed",
                sopralluogo_substato="da_concordare",
            )
            await InspectionWorkflowService._create_claim_event(
                db,
                tenant_id,
                claim.id,
                "inspection_manual_coordination_required",
                {
                    "reason_code": "no_available_cat",
                    "plan_date": plan_date.isoformat(),
                },
            )

        return {
            "generated_routes_count": len(route_event_ids),
            "claims_planned": claims_planned,
            "claims_fallback_manual": len(fallback_claim_ids),
            "skipped_claims": len(active_claim_ids) if not force else 0,
            "route_event_ids": route_event_ids,
            "fallback_claim_ids": fallback_claim_ids,
        }

    @staticmethod
    async def run_route_generation(
        db: AsyncSession,
        tenant_id: str,
        *,
        plan_date: Optional[date] = None,
        force: bool = False,
    ) -> dict:
        local_now = datetime.now(LOCAL_TIMEZONE)
        actual_plan_date = plan_date or (local_now.date() + timedelta(days=INSPECTION_LEAD_DAYS))
        summary = await InspectionWorkflowService._build_route_proposals(
            db,
            tenant_id,
            actual_plan_date,
            force=force,
        )
        automation_state = await InspectionWorkflowService._get_or_create_automation_state(db, tenant_id)
        automation_state.last_route_generation_date = datetime.now(LOCAL_TIMEZONE).date()
        automation_state.last_route_generation_at = datetime.now(timezone.utc)

        tenant_result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
        tenant = tenant_result.scalar_one_or_none()
        if tenant is not None:
            settings_json = dict(tenant.settings_json or {})
            legacy_state = dict(settings_json.get("inspection_automation_state") or {})
            legacy_state["last_route_generation_date"] = automation_state.last_route_generation_date.isoformat()
            legacy_state["last_route_generation_at"] = automation_state.last_route_generation_at.isoformat()
            settings_json["inspection_automation_state"] = legacy_state
            tenant.settings_json = settings_json or None
        await db.commit()
        return {
            "tenant_id": tenant_id,
            "plan_date": actual_plan_date,
            "processed_at": datetime.now(timezone.utc),
            **summary,
        }

    @staticmethod
    async def _replan_for_route_event(
        db: AsyncSession,
        event: CalendarEvent | InspectionRouteProposal,
        *,
        excluded_user_ids: set[str],
    ) -> dict:
        if isinstance(event, InspectionRouteProposal):
            metadata = InspectionWorkflowService._route_projection_metadata(event)
            stops = await InspectionWorkflowService._fetch_route_stops(db, event.id)
            claim_ids = {stop.claim_id for stop in stops if isinstance(stop.claim_id, str)}
            plan_date = event.plan_date
        else:
            metadata = InspectionWorkflowService._route_metadata(event)
            claim_ids = {
                claim_id
                for claim_id in metadata.get("claim_ids", [])
                if isinstance(claim_id, str)
            }
            plan_date = InspectionWorkflowService._parse_date(metadata.get("plan_date"))
        if not claim_ids or plan_date is None:
            return {
                "generated_routes_count": 0,
                "claims_planned": 0,
                "claims_fallback_manual": 0,
                "skipped_claims": 0,
                "route_event_ids": [],
                "fallback_claim_ids": [],
            }
        return await InspectionWorkflowService._build_route_proposals(
            db,
            event.tenant_id,
            plan_date,
            claim_ids=claim_ids,
            excluded_user_ids=excluded_user_ids,
            force=False,
        )

    @staticmethod
    async def reject_route_proposal(
        db: AsyncSession,
        event_id: str,
        *,
        reason_code: str,
        reason: Optional[str],
        actor_user_id: Optional[str],
    ) -> tuple[CalendarEvent, dict]:
        event = await InspectionWorkflowService._fetch_route_event(db, event_id)
        if event is None:
            raise ValueError("Route proposal not found")
        if event.status != "proposed":
            raise ValueError("Route proposal is not pending review")

        now = datetime.now(timezone.utc)
        metadata = InspectionWorkflowService._route_metadata(event)
        history = list(metadata.get("rejection_history", []))
        history.append(
            {
                "occurred_at": now.isoformat(),
                "reason_code": reason_code,
                "reason": reason,
                "actor_user_id": actor_user_id,
            }
        )
        metadata["rejection_history"] = history
        metadata["route_status"] = "rejected"
        metadata["rejection_reason_code"] = reason_code
        metadata["rejection_reason"] = reason
        event.metadata_json = metadata
        event.status = "rejected"
        await InspectionWorkflowService._set_route_projection_status(
            db,
            event.id,
            status="rejected",
            metadata=metadata,
        )

        claim_ids = [
            claim_id
            for claim_id in metadata.get("claim_ids", [])
            if isinstance(claim_id, str)
        ]
        if claim_ids:
            result = await db.execute(
                select(Claim).where(Claim.tenant_id == event.tenant_id, Claim.id.in_(claim_ids))
            )
            for claim in result.scalars().all():
                claim_metadata = InspectionWorkflowService._metadata(claim)
                assignment = dict(claim_metadata.get("inspection_assignment") or {})
                if assignment.get("route_proposal_event_id") == event.id:
                    assignment["route_proposal_event_id"] = None
                    claim_metadata["inspection_assignment"] = assignment
                automation = dict(claim_metadata.get("inspection_automation") or {})
                automation["last_rejection_code"] = reason_code
                automation["last_rejection_reason"] = reason
                automation["last_rejection_at"] = now.isoformat()
                claim_metadata["inspection_automation"] = automation
                InspectionWorkflowService._save_metadata(claim, claim_metadata)
                await InspectionWorkflowService._create_claim_event(
                    db,
                    event.tenant_id,
                    claim.id,
                    "inspection_route_rejected",
                    {
                        "route_event_id": event.id,
                        "reason_code": reason_code,
                        "reason": reason,
                    },
                    actor_user_id=actor_user_id,
                )

        replan_summary = await InspectionWorkflowService._replan_for_route_event(
            db,
            event,
            excluded_user_ids={event.owner_user_id},
        )
        await db.commit()
        await db.refresh(event)
        return event, replan_summary

    @staticmethod
    async def accept_route_proposal(
        db: AsyncSession,
        event_id: str,
        *,
        actor_user_id: Optional[str],
    ) -> CalendarEvent:
        event = await InspectionWorkflowService._fetch_route_event(db, event_id)
        if event is None:
            raise ValueError("Route proposal not found")
        if event.status != "proposed":
            raise ValueError("Route proposal is not pending review")

        metadata = InspectionWorkflowService._route_metadata(event)
        stops = metadata.get("stops", [])
        if not isinstance(stops, list) or not stops:
            raise ValueError("Route proposal has no stops")

        now = datetime.now(timezone.utc)
        event.status = "accepted"
        metadata["route_status"] = "accepted"
        metadata["accepted_at"] = now.isoformat()
        metadata["accepted_by_user_id"] = actor_user_id
        event.metadata_json = metadata
        await InspectionWorkflowService._set_route_projection_status(
            db,
            event.id,
            status="accepted",
            metadata=metadata,
        )

        claim_ids = [
            stop.get("claim_id")
            for stop in stops
            if isinstance(stop, dict) and isinstance(stop.get("claim_id"), str)
        ]
        result = await db.execute(
            select(Claim).where(Claim.tenant_id == event.tenant_id, Claim.id.in_(claim_ids))
        )
        claims_by_id = {claim.id: claim for claim in result.scalars().all()}

        for raw_stop in stops:
            if not isinstance(raw_stop, dict):
                continue
            claim_id = raw_stop.get("claim_id")
            claim = claims_by_id.get(claim_id)
            if claim is None:
                continue
            scheduled_at = InspectionWorkflowService._parse_datetime(raw_stop.get("starts_at"))
            metadata_claim = InspectionWorkflowService._metadata(claim)
            assignment = dict(metadata_claim.get("inspection_assignment") or {})
            assignment.update(
                {
                    "route_proposal_event_id": event.id,
                    "assigned_cat_user_id": event.owner_user_id,
                    "assigned_cat_email": metadata.get("owner_email"),
                    "assigned_cat_name": metadata.get("owner_name"),
                    "accepted_at": now.isoformat(),
                    "planned_slot_start": raw_stop.get("starts_at"),
                    "planned_slot_end": raw_stop.get("ends_at"),
                    "outside_zone": bool(raw_stop.get("outside_zone")),
                }
            )
            metadata_claim["inspection_assignment"] = assignment
            automation = dict(metadata_claim.get("inspection_automation") or {})
            automation["review_deadline"] = metadata.get("review_deadline")
            automation["appointment_confirmed_at"] = now.isoformat()
            metadata_claim["inspection_automation"] = automation
            InspectionWorkflowService._save_metadata(claim, metadata_claim)
            preferences = InspectionWorkflowService._preferences_metadata(claim)
            description_parts = ["Sopralluogo confermato dal CAT"]
            if preferences.get("notes"):
                description_parts.append(str(preferences.get("notes")))
            db.add(
                CalendarEvent(
                    id=str(uuid.uuid4()),
                    tenant_id=event.tenant_id,
                    claim_id=claim.id,
                    owner_user_id=event.owner_user_id,
                    title=f"Sopralluogo {raw_stop.get('claim_reference') or claim.external_ref or claim.numero_sinistro or claim.id}",
                    description=" · ".join(description_parts),
                    event_type=CONFIRMED_APPOINTMENT_EVENT_TYPE,
                    starts_at=scheduled_at or event.starts_at,
                    ends_at=InspectionWorkflowService._parse_datetime(raw_stop.get("ends_at")) or event.ends_at,
                    location=preferences.get("address_line") or claim.indirizzo_assicurato,
                    status="confirmed",
                    visibility="tenant",
                    source="inspection_automation",
                    metadata_json={
                        "route_event_id": event.id,
                        "claim_reference": raw_stop.get("claim_reference") or claim.external_ref or claim.numero_sinistro or claim.id,
                        "outside_zone": bool(raw_stop.get("outside_zone")),
                    },
                )
            )
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                ClaimStatus.SOPRALLUOGO.value,
                reason="inspection_route_accepted",
                payload={"scheduled_at": scheduled_at.isoformat() if scheduled_at else None},
                sopralluogo_substato="fissato",
            )
            await InspectionWorkflowService._create_claim_event(
                db,
                event.tenant_id,
                claim.id,
                "inspection_appointment_confirmed",
                {
                    "route_event_id": event.id,
                    "scheduled_at": scheduled_at.isoformat() if scheduled_at else None,
                    "cat_user_id": event.owner_user_id,
                },
                actor_user_id=actor_user_id,
            )

        await db.commit()
        await db.refresh(event)
        return event

    @staticmethod
    async def list_route_proposals(
        db: AsyncSession,
        tenant_id: str,
        *,
        owner_user_id: Optional[str] = None,
        status_filter: Optional[str] = None,
        plan_date: Optional[date] = None,
    ) -> list[CalendarEvent]:
        proposals = await InspectionWorkflowService._list_route_projection_records(
            db,
            tenant_id,
            owner_user_id=owner_user_id,
            status_filter=status_filter,
            plan_date=plan_date,
        )
        if proposals:
            route_ids = [item.id for item in proposals]
            result = await db.execute(
                select(CalendarEvent).where(
                    CalendarEvent.id.in_(route_ids),
                    CalendarEvent.event_type == ROUTE_PROPOSAL_EVENT_TYPE,
                )
            )
            event_map = {event.id: event for event in result.scalars().all()}
            items: list[CalendarEvent] = []
            for proposal in proposals:
                event = event_map.get(proposal.id)
                if event is not None:
                    items.append(event)
            if items:
                return items

        query = select(CalendarEvent).where(
            CalendarEvent.tenant_id == tenant_id,
            CalendarEvent.event_type == ROUTE_PROPOSAL_EVENT_TYPE,
        )
        if owner_user_id:
            query = query.where(CalendarEvent.owner_user_id == owner_user_id)
        if status_filter:
            query = query.where(CalendarEvent.status == status_filter)
        result = await db.execute(query.order_by(CalendarEvent.starts_at.asc()))
        items = list(result.scalars().all())
        if plan_date is None:
            return items
        return [
            item
            for item in items
            if InspectionWorkflowService._route_metadata(item).get("plan_date") == plan_date.isoformat()
        ]

    @staticmethod
    async def process_expired_route_proposals(
        db: AsyncSession,
        tenant_id: str,
        *,
        now: Optional[datetime] = None,
    ) -> dict:
        current_time = now or datetime.now(timezone.utc)
        proposals = await InspectionWorkflowService.list_route_proposals(
            db,
            tenant_id,
            status_filter="proposed",
        )
        expired_routes = 0
        replanned_routes = 0
        manual_fallback_claims = 0
        for proposal in proposals:
            metadata = InspectionWorkflowService._route_metadata(proposal)
            review_deadline = InspectionWorkflowService._parse_datetime(metadata.get("review_deadline"))
            if review_deadline is None or review_deadline > current_time:
                continue
            _, replan_summary = await InspectionWorkflowService.reject_route_proposal(
                db,
                proposal.id,
                reason_code="review_window_expired",
                reason="Scaduta la finestra di review del CAT",
                actor_user_id=None,
            )
            expired_routes += 1
            replanned_routes += replan_summary["generated_routes_count"]
            manual_fallback_claims += replan_summary["claims_fallback_manual"]

        return {
            "processed_at": current_time,
            "expired_routes_count": expired_routes,
            "replanned_routes_count": replanned_routes,
            "manual_fallback_claims": manual_fallback_claims,
        }

    @staticmethod
    def _should_run_daily_generation(
        tenant: Tenant,
        automation_state: Optional[InspectionTenantAutomationState],
        route_generation_hour: int,
        local_now: datetime,
    ) -> bool:
        if local_now.hour < route_generation_hour:
            return False
        if automation_state is not None and automation_state.last_route_generation_date is not None:
            return automation_state.last_route_generation_date != local_now.date()
        settings_json = dict(tenant.settings_json or {})
        legacy_state = dict(settings_json.get("inspection_automation_state") or {})
        return legacy_state.get("last_route_generation_date") != local_now.date().isoformat()

    @staticmethod
    async def run_due_automation_cycle(db: AsyncSession) -> None:
        if not settings.FF_INSPECTION_AUTOMATIONS_ENABLED:
            return

        tenants_result = await db.execute(select(Tenant))
        tenants = tenants_result.scalars().all()
        for tenant in tenants:
            try:
                _, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant.id)
                if not cat_settings.enabled:
                    continue

                await InspectionWorkflowService.process_expired_route_proposals(db, tenant.id)

                local_now = datetime.now(LOCAL_TIMEZONE)
                automation_state = await InspectionWorkflowService._get_or_create_automation_state(db, tenant.id)
                if InspectionWorkflowService._should_run_daily_generation(
                    tenant,
                    automation_state,
                    cat_settings.planner.route_generation_hour,
                    local_now,
                ):
                    await InspectionWorkflowService.run_route_generation(
                        db,
                        tenant.id,
                        plan_date=local_now.date() + timedelta(days=INSPECTION_LEAD_DAYS),
                    )
                    settings_json = dict(tenant.settings_json or {})
                    automation_state = dict(settings_json.get("inspection_automation_state") or {})
                    automation_state["last_route_generation_date"] = local_now.date().isoformat()
                    automation_state["last_route_generation_at"] = datetime.now(timezone.utc).isoformat()
                    settings_json["inspection_automation_state"] = automation_state
                    tenant.settings_json = settings_json
                    automation_state_row = await InspectionWorkflowService._get_or_create_automation_state(db, tenant.id)
                    automation_state_row.last_route_generation_date = local_now.date()
                    automation_state_row.last_route_generation_at = datetime.now(timezone.utc)
                    await db.commit()
            except Exception:
                logger.exception("Inspection automation cycle failed for tenant %s", tenant.id)
                await db.rollback()


class InspectionAutomationRuntime:
    _task: Optional[asyncio.Task] = None
    _stop_event: Optional[asyncio.Event] = None

    @classmethod
    async def start(cls) -> None:
        if not settings.FF_INSPECTION_AUTOMATIONS_ENABLED or cls._task is not None:
            return
        cls._stop_event = asyncio.Event()
        cls._task = asyncio.create_task(cls._runner(), name="inspection-automation-runtime")

    @classmethod
    async def stop(cls) -> None:
        if cls._stop_event is not None:
            cls._stop_event.set()
        if cls._task is not None:
            try:
                await cls._task
            finally:
                cls._task = None
                cls._stop_event = None

    @classmethod
    async def _runner(cls) -> None:
        assert cls._stop_event is not None
        while not cls._stop_event.is_set():
            try:
                async with AsyncSessionLocal() as session:
                    await InspectionWorkflowService.run_due_automation_cycle(session)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Inspection automation runtime loop failed")

            try:
                await asyncio.wait_for(
                    cls._stop_event.wait(),
                    timeout=max(10, settings.INSPECTION_AUTOMATION_POLL_SECONDS),
                )
            except asyncio.TimeoutError:
                continue
