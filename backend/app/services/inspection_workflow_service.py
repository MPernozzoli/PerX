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
from app.models.planning import CalendarEvent, UserWorkSchedule
from app.models.role import Role, user_roles
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.inspection import (
    InspectionManualAppointmentCreate,
    InspectionSchedulingPreferencesUpsert,
)
from app.schemas.tenant_settings import TenantCATPOI, TenantCATSettingsPayload
from app.services.claim_service import ClaimService
from app.services.state_service import StateService

logger = logging.getLogger(__name__)

LOCAL_TIMEZONE = ZoneInfo("Europe/Rome")
ROUTE_PROPOSAL_EVENT_TYPE = "cat_route_proposal"
CONFIRMED_APPOINTMENT_EVENT_TYPE = "inspection_appointment"
INSPECTION_LEAD_DAYS = 2
AUTO_ENTRY_STATES = {"SV006", "SV007", "SV008", "SV009", "SV015", "SV053"}
CAT_ACTIVE_STATES = {"SV052", "SV053", "SV050"}


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
    def _duration_minutes_for_claim(claim: Claim, preferences: dict) -> int:
        requested = preferences.get("requested_duration_minutes")
        if isinstance(requested, int):
            return max(15, min(60, requested))

        metadata = InspectionWorkflowService._metadata(claim)
        goods_count = metadata.get("numero_beni")
        try:
            goods_count = int(goods_count)
        except (TypeError, ValueError):
            goods_count = 1

        complexity = InspectionWorkflowService._normalize_text(claim.complessita)
        duration = 15 + max(goods_count - 1, 0) * 5
        if "alta" in complexity or "high" in complexity:
            duration += 20
        elif "media" in complexity or "medium" in complexity:
            duration += 10
        return max(15, min(60, duration))

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
    def _preferred_windows_for_plan_date(
        claim: Claim,
        plan_date: date,
        tolerance_percent: int,
    ) -> list[dict]:
        preferences = InspectionWorkflowService._preferences_metadata(claim)
        slots = preferences.get("preferred_slots")
        if not isinstance(slots, list):
            return []

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
            tolerance_minutes = int(slot_minutes * max(tolerance_percent, 0) / 100)
            allowed_start = preferred_start - timedelta(minutes=tolerance_minutes)
            allowed_end = preferred_end + timedelta(minutes=tolerance_minutes)
            windows.append(
                {
                    "label": raw_slot.get("label"),
                    "preferred_start": preferred_start,
                    "preferred_end": preferred_end,
                    "allowed_start": allowed_start,
                    "allowed_end": allowed_end,
                    "slot_minutes": slot_minutes,
                    "tolerance_minutes": tolerance_minutes,
                }
            )
        return sorted(windows, key=lambda item: item["preferred_start"])

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
            context.busy_intervals = sorted(
                schedules_by_user.get(context.user_id, []) + busy_by_user.get(context.user_id, []),
                key=lambda item: item[0],
            )
            # Keep only working intervals if available. Busy intervals are appended again later as needed.
            context.busy_intervals = busy_by_user.get(context.user_id, [])
            context.provisional_stops = []
            setattr(context, "working_intervals", sorted(schedules_by_user.get(context.user_id, []), key=lambda item: item[0]))
        return contexts

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

        best: Optional[tuple[ProposedStop, float]] = None
        last_stop = InspectionWorkflowService._last_provisional_stop(technician)
        for window in claim_context.preferred_windows:
            for free_start, free_end in free_intervals:
                interval_start = max(free_start, window["allowed_start"])
                interval_end = min(free_end, window["allowed_end"])
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
                travel_minutes = InspectionWorkflowService._estimate_travel_minutes(distance_from_previous)
                earliest_start = interval_start
                if last_stop is not None:
                    earliest_start = max(earliest_start, last_stop.ends_at + timedelta(minutes=travel_minutes))

                proposed_end = earliest_start + timedelta(minutes=claim_context.duration_minutes)
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
                    duration_minutes=claim_context.duration_minutes,
                    preferred_start=window["preferred_start"],
                )
                if best is None or score < best[1]:
                    best = (stop, score)
        return best

    @staticmethod
    async def _transition_claim(
        db: AsyncSession,
        claim: Claim,
        to_state: str,
        *,
        reason: Optional[str] = None,
        payload: Optional[dict] = None,
    ) -> None:
        if claim.stato_corrente == to_state:
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

        if claim.stato_corrente in AUTO_ENTRY_STATES:
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                "SV052",
                reason="inspection_preferences_confirmed",
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

        if claim.stato_corrente not in {"SV052", "SV053", "SV050"}:
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                "SV053",
                reason="manual_inspection_appointment",
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
            "SV050",
            reason="manual_inspection_appointment_confirmed",
            payload={"scheduled_at": start_at.isoformat()},
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
            Claim.stato_corrente == "SV052",
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
    async def _build_route_proposals(
        db: AsyncSession,
        tenant_id: str,
        plan_date: date,
        *,
        claim_ids: Optional[set[str]] = None,
        excluded_user_ids: Optional[set[str]] = None,
        force: bool = False,
    ) -> dict:
        _, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, tenant_id)
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
        route_event_ids: list[str] = []
        claims_planned = 0
        for technician in technicians:
            stops = sorted(technician.provisional_stops, key=lambda item: item.starts_at)
            if not stops:
                continue
            total_duration_minutes = int(sum(stop.duration_minutes for stop in stops))
            total_distance_km = round(sum(stop.distance_from_previous_km for stop in stops), 1)
            review_deadline = now + timedelta(minutes=cat_settings.planner.route_review_window_minutes)
            event = CalendarEvent(
                id=str(uuid.uuid4()),
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
                metadata_json={
                    "route_status": "proposed",
                    "plan_date": plan_date.isoformat(),
                    "review_deadline": review_deadline.isoformat(),
                    "claim_ids": [stop.claim_id for stop in stops],
                    "generated_at": now.isoformat(),
                    "generated_by": "inspection_automation",
                    "has_configured_poi": technician.has_configured_poi,
                    "total_distance_km": total_distance_km,
                    "total_duration_minutes": total_duration_minutes,
                    "stops": [
                        {
                            "claim_id": stop.claim_id,
                            "claim_reference": stop.claim_reference,
                            "starts_at": stop.starts_at.isoformat(),
                            "ends_at": stop.ends_at.isoformat(),
                            "municipality": stop.municipality,
                            "province": stop.province,
                            "region": stop.region,
                            "masked_location": stop.masked_location,
                            "outside_zone": stop.outside_zone,
                            "distance_from_previous_km": stop.distance_from_previous_km,
                            "duration_minutes": stop.duration_minutes,
                        }
                        for stop in stops
                    ],
                    "rejection_history": [],
                },
            )
            db.add(event)
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
                "SV053",
                reason="inspection_auto_planning_failed",
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
        event: CalendarEvent,
        *,
        excluded_user_ids: set[str],
    ) -> dict:
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
                    "accepted_at": now.isoformat(),
                    "planned_slot_start": raw_stop.get("starts_at"),
                    "planned_slot_end": raw_stop.get("ends_at"),
                    "outside_zone": bool(raw_stop.get("outside_zone")),
                }
            )
            metadata_claim["inspection_assignment"] = assignment
            automation = dict(metadata_claim.get("inspection_automation") or {})
            automation["review_deadline"] = metadata.get("review_deadline")
            metadata_claim["inspection_automation"] = automation
            InspectionWorkflowService._save_metadata(claim, metadata_claim)
            await InspectionWorkflowService._transition_claim(
                db,
                claim,
                "SV050",
                reason="inspection_route_accepted",
                payload={"scheduled_at": scheduled_at.isoformat() if scheduled_at else None},
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
        route_generation_hour: int,
        local_now: datetime,
    ) -> bool:
        if local_now.hour < route_generation_hour:
            return False
        settings_json = dict(tenant.settings_json or {})
        automation_state = dict(settings_json.get("inspection_automation_state") or {})
        return automation_state.get("last_route_generation_date") != local_now.date().isoformat()

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
                if InspectionWorkflowService._should_run_daily_generation(
                    tenant,
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

