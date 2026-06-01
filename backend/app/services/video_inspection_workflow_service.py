"""
Portal scheduling and same-day automatic assignment for video inspections.
"""
from __future__ import annotations

import asyncio
from datetime import date, datetime, time, timedelta, timezone
import logging
from typing import Optional
import uuid
from zoneinfo import ZoneInfo

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.claim_status import ClaimStatus
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.claim import Claim
from app.models.claim_assignment import ClaimAssignment
from app.models.claim_event import ClaimEvent
from app.models.planning import CalendarEvent, UserWorkSchedule
from app.models.role import Role, user_roles
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.inspection import InspectionPreferredSlotInput
from app.services.insured_notification_service import (
    InsuredNotificationService,
    build_portal_deeplink,
)
from app.services.state_service import VIDEOPERIZIA_AUTO_SUBSTATI

logger = logging.getLogger(__name__)

LOCAL_TIMEZONE = ZoneInfo("Europe/Rome")
VIDEO_INSPECTION_EVENT_TYPE = "video_inspection_appointment"
VIDEO_INSPECTION_PREPARATION_ITEMS = [
    "Sarà necessario inquadrare l'esterno del fabbricato.",
    "Sarà necessario condividere la posizione in tempo reale durante la chiamata.",
    "Usa uno smartphone o tablet con una buona connessione internet e una buona telecamera.",
    "Prepara tutti i beni e componenti da mostrare: gli elementi non visionati non potranno essere portati a stima.",
    "Assicurati che ci sia illuminazione adeguata negli ambienti da riprendere.",
]


class VideoInspectionWorkflowService:
    @staticmethod
    def _metadata(claim: Claim) -> dict:
        return dict(claim.metadata_json or {})

    @staticmethod
    def _preferences(claim: Claim) -> dict:
        value = VideoInspectionWorkflowService._metadata(claim).get("video_inspection_preferences")
        return dict(value) if isinstance(value, dict) else {}

    @staticmethod
    def _tenant_settings(tenant: Tenant) -> dict:
        raw = (tenant.settings_json or {}).get("video_inspection_settings")
        return dict(raw) if isinstance(raw, dict) else {}

    @staticmethod
    def _parse_time(value: object, fallback: time) -> time:
        if isinstance(value, time):
            return value
        if isinstance(value, str):
            try:
                return time.fromisoformat(value)
            except ValueError:
                pass
        return fallback

    @staticmethod
    def _combine_local(day: date, value: time) -> datetime:
        return datetime.combine(day, value, tzinfo=LOCAL_TIMEZONE).astimezone(timezone.utc)

    @staticmethod
    def _selected_slots(preferences: dict) -> list[dict]:
        items: list[dict] = []
        for raw in preferences.get("preferred_slots") or []:
            if not isinstance(raw, dict):
                continue
            try:
                slot_date = date.fromisoformat(raw["date"])
                start = time.fromisoformat(raw["start_time"])
                end = time.fromisoformat(raw["end_time"])
            except (KeyError, TypeError, ValueError):
                continue
            starts_at = VideoInspectionWorkflowService._combine_local(slot_date, start)
            ends_at = VideoInspectionWorkflowService._combine_local(slot_date, end)
            items.append(
                {
                    "id": starts_at.isoformat(),
                    "date": slot_date.isoformat(),
                    "start_at": starts_at,
                    "end_at": ends_at,
                    "label": raw.get("label") or f"{start.strftime('%H:%M')} - {end.strftime('%H:%M')}",
                }
            )
        return sorted(items, key=lambda item: item["start_at"])

    @staticmethod
    def _expert_config(user: User) -> dict:
        raw = (user.settings_json or {}).get("video_inspection")
        return dict(raw) if isinstance(raw, dict) else {}

    @staticmethod
    def _expert_supports_claim(user: User, claim: Claim) -> bool:
        config = VideoInspectionWorkflowService._expert_config(user)
        if not bool(config.get("enabled")):
            return False
        companies = {str(item).strip().lower() for item in config.get("companies") or [] if str(item).strip()}
        if companies and (claim.compagnia or "").strip().lower() not in companies:
            return False
        excluded_policies = {
            str(item).strip().lower()
            for item in config.get("excluded_policy_numbers") or []
            if str(item).strip()
        }
        if (claim.numero_polizza or "").strip().lower() in excluded_policies:
            return False
        return True

    @staticmethod
    async def _eligible_experts(db: AsyncSession, tenant_id: str, claim: Claim) -> list[User]:
        result = await db.execute(
            select(User)
            .join(user_roles, user_roles.c.user_id == User.id)
            .join(Role, Role.id == user_roles.c.role_id)
            .where(
                User.tenant_id == tenant_id,
                User.is_active == True,
                Role.name.in_(["perito", "expert"]),
            )
            .order_by(User.full_name.asc())
        )
        unique = {user.id: user for user in result.scalars().all()}
        return [user for user in unique.values() if VideoInspectionWorkflowService._expert_supports_claim(user, claim)]

    @staticmethod
    async def _active_assignment_and_expert(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
    ) -> tuple[ClaimAssignment | None, User | None]:
        result = await db.execute(
            select(ClaimAssignment, User)
            .join(User, User.id == ClaimAssignment.assignee_user_id)
            .where(
                ClaimAssignment.tenant_id == tenant_id,
                ClaimAssignment.claim_id == claim.id,
                ClaimAssignment.unassigned_at.is_(None),
                User.tenant_id == tenant_id,
                User.is_active == True,
            )
            .order_by(ClaimAssignment.assigned_at.desc())
            .limit(1)
        )
        row = result.first()
        if row is not None:
            return row[0], row[1]

        owner_email = (claim.owner_email or "").strip().lower()
        if not owner_email:
            return None, None
        owner_result = await db.execute(
            select(User)
            .join(user_roles, user_roles.c.user_id == User.id)
            .join(Role, Role.id == user_roles.c.role_id)
            .where(
                User.tenant_id == tenant_id,
                User.is_active == True,
                func.lower(User.email) == owner_email,
                Role.name.in_(["perito", "expert"]),
            )
            .limit(1)
        )
        return None, owner_result.scalar_one_or_none()

    @staticmethod
    def _scheduling_experts(retained_expert: User | None, eligible_experts: list[User]) -> tuple[list[User], bool]:
        if retained_expert is not None:
            return [retained_expert], True
        return eligible_experts, False

    @staticmethod
    async def _busy_intervals(db: AsyncSession, user_ids: list[str], day: date) -> dict[str, list[tuple[datetime, datetime]]]:
        if not user_ids:
            return {}
        range_start = VideoInspectionWorkflowService._combine_local(day, time.min)
        range_end = VideoInspectionWorkflowService._combine_local(day + timedelta(days=1), time.min)
        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.owner_user_id.in_(user_ids),
                CalendarEvent.starts_at < range_end,
                CalendarEvent.ends_at > range_start,
                CalendarEvent.status.in_(["confirmed", "proposed", "accepted"]),
            )
        )
        busy = {user_id: [] for user_id in user_ids}
        for event in result.scalars().all():
            busy[event.owner_user_id].append((event.starts_at, event.ends_at))
        return busy

    @staticmethod
    async def _working_intervals(db: AsyncSession, tenant_id: str, user_ids: list[str], day: date) -> dict[str, list[tuple[datetime, datetime]]]:
        if not user_ids:
            return {}
        python_weekday = day.weekday()
        apple_weekday = ((python_weekday + 1) % 7) + 1
        result = await db.execute(
            select(UserWorkSchedule).where(
                UserWorkSchedule.tenant_id == tenant_id,
                UserWorkSchedule.user_id.in_(user_ids),
                UserWorkSchedule.weekday.in_([python_weekday, apple_weekday]),
                or_(UserWorkSchedule.effective_from.is_(None), UserWorkSchedule.effective_from <= day),
                or_(UserWorkSchedule.effective_to.is_(None), UserWorkSchedule.effective_to >= day),
            )
        )
        intervals = {user_id: [] for user_id in user_ids}
        for schedule in result.scalars().all():
            start_at = VideoInspectionWorkflowService._combine_local(day, schedule.start_time)
            end_at = VideoInspectionWorkflowService._combine_local(day, schedule.end_time)
            if end_at > start_at:
                intervals[schedule.user_id].append((start_at, end_at))
        return intervals

    @staticmethod
    def _interval_is_available(
        starts_at: datetime,
        ends_at: datetime,
        working: list[tuple[datetime, datetime]],
        busy: list[tuple[datetime, datetime]],
    ) -> bool:
        is_working = any(work_start <= starts_at and ends_at <= work_end for work_start, work_end in working)
        return is_working and not any(starts_at < busy_end and ends_at > busy_start for busy_start, busy_end in busy)

    @staticmethod
    async def get_portal_scheduling_overview(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        horizon_days: int = 14,
    ) -> dict:
        claim = await db.get(Claim, claim_id)
        if claim is None or claim.tenant_id != tenant_id:
            raise ValueError("Claim not found")
        tenant = await db.get(Tenant, tenant_id)
        if tenant is None:
            raise ValueError("Tenant not found")
        config = VideoInspectionWorkflowService._tenant_settings(tenant)
        start_time = VideoInspectionWorkflowService._parse_time(config.get("first_slot_time"), time(hour=10))
        slot_minutes = max(15, int(config.get("slot_minutes") or 30))
        assignment_run_hour = int(config.get("assignment_run_hour") or 9)
        selected_slots = VideoInspectionWorkflowService._selected_slots(VideoInspectionWorkflowService._preferences(claim))
        _, retained_expert = await VideoInspectionWorkflowService._active_assignment_and_expert(db, tenant_id, claim)
        eligible_experts = (
            [] if retained_expert is not None
            else await VideoInspectionWorkflowService._eligible_experts(db, tenant_id, claim)
        )
        experts, assigned_expert_retained = VideoInspectionWorkflowService._scheduling_experts(
            retained_expert,
            eligible_experts,
        )
        expert_ids = [expert.id for expert in experts]
        now = datetime.now(timezone.utc)
        availability_days: list[dict] = []
        for offset in range(horizon_days):
            day = now.astimezone(LOCAL_TIMEZONE).date() + timedelta(days=offset)
            working = await VideoInspectionWorkflowService._working_intervals(db, tenant_id, expert_ids, day)
            busy = await VideoInspectionWorkflowService._busy_intervals(db, expert_ids, day)
            day_slots: list[dict] = []
            cursor = VideoInspectionWorkflowService._combine_local(day, start_time)
            day_end = VideoInspectionWorkflowService._combine_local(day + timedelta(days=1), time.min)
            duration = timedelta(minutes=slot_minutes)
            while cursor + duration <= day_end:
                end = cursor + duration
                compatible_ids = [
                    expert.id
                    for expert in experts
                    if cursor > now
                    and VideoInspectionWorkflowService._interval_is_available(
                        cursor,
                        end,
                        working.get(expert.id, []),
                        busy.get(expert.id, []),
                    )
                ]
                if compatible_ids:
                    day_slots.append(
                        {
                            "id": cursor.isoformat(),
                            "date": day.isoformat(),
                            "start_at": cursor,
                            "end_at": end,
                            "label": f"{cursor.astimezone(LOCAL_TIMEZONE).strftime('%H:%M')} - {end.astimezone(LOCAL_TIMEZONE).strftime('%H:%M')}",
                            "available_cat_count": len(compatible_ids),
                            "candidate_user_ids": compatible_ids,
                        }
                    )
                cursor = end
            availability_days.append(
                {
                    "date": day.isoformat(),
                    "weekday_label": day.strftime("%A"),
                    "is_available": bool(day_slots),
                    "slot_count": len(day_slots),
                    "slots": day_slots,
                }
            )
        appointment = await VideoInspectionWorkflowService._appointment_for_claim(db, tenant_id, claim_id)
        return {
            "enabled": True,
            "mode": "video_inspection",
            "status": "confirmed" if appointment else ("pending_confirmation" if selected_slots else "selection_required"),
            "workflow_stage": "video_inspection_scheduling",
            "instructions": (
                f"Il perito incaricato {retained_expert.full_name} resta assegnato alla pratica. "
                f"Scegli una finestra di {slot_minutes} minuti: mostriamo solo i suoi orari liberi."
                if assigned_expert_retained
                else (
                    f"Scegli una finestra di {slot_minutes} minuti per la videoperizia. "
                    f"Alle ore {assignment_run_hour:02d}:00 del giorno selezionato "
                    "il sistema assegnerà il primo perito compatibile in base a disponibilità e carico di lavoro."
                )
            ),
            "pending_confirmation_message": (
                (
                    f"La preferenza è registrata. Il perito incaricato resta {retained_expert.full_name}."
                    if assigned_expert_retained
                    else "La preferenza è registrata. Il giorno dell'appuntamento riceverai il nome del perito assegnato."
                )
                if selected_slots and not appointment else None
            ),
            "address_confirmed": True,
            "location": {},
            "selected_slots": selected_slots,
            "availability_days": availability_days,
            "candidate_cats": [],
            "route_review_deadline": None,
            "route_proposal_event_id": None,
            "slot_duration_minutes": slot_minutes,
            "assignment_run_hour": assignment_run_hour,
            "assigned_expert_name": retained_expert.full_name if retained_expert is not None else None,
            "assigned_expert_retained": assigned_expert_retained,
            "preparation_items": VIDEO_INSPECTION_PREPARATION_ITEMS,
        }

    @staticmethod
    async def submit_portal_preferences(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        selected_slots: list[InspectionPreferredSlotInput],
        notes: Optional[str],
    ) -> Claim:
        claim = await db.get(Claim, claim_id)
        if claim is None or claim.tenant_id != tenant_id:
            raise ValueError("Claim not found")
        if claim.stato_corrente != ClaimStatus.VIDEOPERIZIA.value:
            raise ValueError("Video inspection scheduling is not enabled for this claim")
        if len(selected_slots) != 1:
            raise ValueError("Select exactly one video inspection time slot")
        tenant = await db.get(Tenant, tenant_id)
        if tenant is None:
            raise ValueError("Tenant not found")
        config = VideoInspectionWorkflowService._tenant_settings(tenant)
        expected_minutes = max(15, int(config.get("slot_minutes") or 30))
        selected = selected_slots[0]
        selected_start = VideoInspectionWorkflowService._combine_local(selected.date, selected.start_time)
        selected_end = VideoInspectionWorkflowService._combine_local(selected.date, selected.end_time)
        selected_minutes = int((selected_end - selected_start).total_seconds() / 60)
        if selected_minutes != expected_minutes:
            raise ValueError(f"Video inspection slots must be {expected_minutes} minutes long")
        if selected_start <= datetime.now(timezone.utc):
            raise ValueError("Video inspection time slot must be in the future")
        overview = await VideoInspectionWorkflowService.get_portal_scheduling_overview(db, tenant_id, claim_id)
        offered_slots = {
            (slot["start_at"], slot["end_at"])
            for day in overview["availability_days"]
            for slot in day["slots"]
        }
        if (selected_start, selected_end) not in offered_slots:
            raise ValueError("Video inspection time slot is no longer available")
        metadata = VideoInspectionWorkflowService._metadata(claim)
        metadata["video_inspection_preferences"] = {
            "preferred_slots": [
                {
                    "date": slot.date.isoformat(),
                    "start_time": slot.start_time.isoformat(timespec="minutes"),
                    "end_time": slot.end_time.isoformat(timespec="minutes"),
                    "label": slot.label,
                }
                for slot in selected_slots
            ],
            "notes": notes,
            "confirmed_at": datetime.now(timezone.utc).isoformat(),
        }
        claim.metadata_json = metadata
        kept = [s for s in (claim.stato_substati or []) if s.get("tag") not in VIDEOPERIZIA_AUTO_SUBSTATI]
        kept.append({"tag": "fissata", "source": "system", "added_at": datetime.utcnow().isoformat()})
        claim.stato_substati = kept
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="video_inspection_preferences_confirmed",
                event_time=datetime.now(timezone.utc),
                source="portal",
                data_json={"preferred_slots_count": len(selected_slots)},
            )
        )
        await db.commit()
        await db.refresh(claim)
        slot_label = selected_slots[0].label or "lo slot scelto"
        slot_date = selected_slots[0].date.strftime("%d/%m/%Y")
        await InsuredNotificationService.notify(
            db, claim,
            kind="video_inspection_fissata",
            title="Videoperizia prenotata",
            body=(
                f"Abbiamo registrato la tua scelta per il {slot_date} ({slot_label}). "
                + (
                    f"Il perito incaricato resta {overview['assigned_expert_name']}."
                    if overview["assigned_expert_retained"]
                    else "Il giorno dell'appuntamento ti comunicheremo il nome del perito assegnato."
                )
            ),
            deeplink=build_portal_deeplink(claim, "videoperizia"),
        )
        return claim

    @staticmethod
    async def _appointment_for_claim(db: AsyncSession, tenant_id: str, claim_id: str) -> CalendarEvent | None:
        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.tenant_id == tenant_id,
                CalendarEvent.claim_id == claim_id,
                CalendarEvent.event_type == VIDEO_INSPECTION_EVENT_TYPE,
                CalendarEvent.status == "confirmed",
            )
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def run_due_assignments(db: AsyncSession, tenant: Tenant, local_now: datetime) -> None:
        config = VideoInspectionWorkflowService._tenant_settings(tenant)
        if not bool(config.get("enabled", True)):
            return
        if local_now.hour < int(config.get("assignment_run_hour") or 9):
            return
        metadata = dict(tenant.settings_json or {})
        state = dict(metadata.get("video_inspection_automation_state") or {})
        if state.get("last_assignment_date") == local_now.date().isoformat():
            return
        result = await db.execute(
            select(Claim).where(
                Claim.tenant_id == tenant.id,
                Claim.stato_corrente == ClaimStatus.VIDEOPERIZIA.value,
            )
        )
        for claim in result.scalars().all():
            await VideoInspectionWorkflowService._assign_claim_for_day(db, claim, local_now.date())
        state["last_assignment_date"] = local_now.date().isoformat()
        state["last_assignment_at"] = datetime.now(timezone.utc).isoformat()
        metadata["video_inspection_automation_state"] = state
        tenant.settings_json = metadata
        await db.commit()

    @staticmethod
    async def _assign_claim_for_day(db: AsyncSession, claim: Claim, day: date) -> None:
        slots = [
            item for item in VideoInspectionWorkflowService._selected_slots(VideoInspectionWorkflowService._preferences(claim))
            if item["date"] == day.isoformat()
        ]
        if not slots or await VideoInspectionWorkflowService._appointment_for_claim(db, claim.tenant_id, claim.id):
            return
        _, retained_expert = await VideoInspectionWorkflowService._active_assignment_and_expert(
            db,
            claim.tenant_id,
            claim,
        )
        eligible_experts = (
            [] if retained_expert is not None
            else await VideoInspectionWorkflowService._eligible_experts(db, claim.tenant_id, claim)
        )
        experts, assigned_expert_retained = VideoInspectionWorkflowService._scheduling_experts(
            retained_expert,
            eligible_experts,
        )
        expert_ids = [expert.id for expert in experts]
        working = await VideoInspectionWorkflowService._working_intervals(db, claim.tenant_id, expert_ids, day)
        busy = await VideoInspectionWorkflowService._busy_intervals(db, expert_ids, day)
        load_result = await db.execute(
            select(ClaimAssignment.assignee_user_id, func.count(ClaimAssignment.id))
            .where(
                ClaimAssignment.tenant_id == claim.tenant_id,
                ClaimAssignment.assignee_user_id.in_(expert_ids),
                ClaimAssignment.unassigned_at.is_(None),
            )
            .group_by(ClaimAssignment.assignee_user_id)
        )
        workload = dict(load_result.all())
        for slot in slots:
            compatible = [
                expert for expert in experts
                if VideoInspectionWorkflowService._interval_is_available(
                    slot["start_at"], slot["end_at"], working.get(expert.id, []), busy.get(expert.id, [])
                )
            ]
            if not compatible:
                continue
            expert = (
                compatible[0]
                if assigned_expert_retained
                else min(compatible, key=lambda item: (workload.get(item.id, 0), item.full_name.lower()))
            )
            await VideoInspectionWorkflowService._confirm_assignment(db, claim, expert, slot["start_at"], slot["end_at"])
            return

    @staticmethod
    async def _confirm_assignment(db: AsyncSession, claim: Claim, expert: User, starts_at: datetime, ends_at: datetime) -> None:
        now = datetime.now(timezone.utc)
        active_assignment, retained_expert = await VideoInspectionWorkflowService._active_assignment_and_expert(
            db,
            claim.tenant_id,
            claim,
        )
        if retained_expert is not None and retained_expert.id != expert.id:
            raise ValueError("Claim is already assigned to another expert")
        if active_assignment is None:
            db.add(
                ClaimAssignment(
                    id=str(uuid.uuid4()),
                    tenant_id=claim.tenant_id,
                    claim_id=claim.id,
                    assignee_user_id=expert.id,
                    assigned_at=now,
                    reason=(
                        "video_inspection_existing_owner_projection"
                        if retained_expert is not None
                        else "video_inspection_automatic_assignment"
                    ),
                )
            )
        db.add(
            CalendarEvent(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                owner_user_id=expert.id,
                title="Videoperizia",
                description=f"Videoperizia sinistro {claim.external_ref or claim.numero_sinistro or claim.id}",
                event_type=VIDEO_INSPECTION_EVENT_TYPE,
                starts_at=starts_at,
                ends_at=ends_at,
                status="confirmed",
                source="video_inspection_automation",
                metadata_json={"assigned_expert_name": expert.full_name},
            )
        )
        claim.owner_email = expert.email
        claim.data_assegnazione = now
        # Lo stato resta VIDEOPERIZIA; il substato passa a "da_eseguire" ora che il perito è assegnato.
        # La transizione a DA_GESTIRE_VIDEO avverrà alla chiusura della videochiamata.
        kept = [s for s in (claim.stato_substati or []) if s.get("tag") not in VIDEOPERIZIA_AUTO_SUBSTATI]
        kept.append({"tag": "da_eseguire", "source": "system", "added_at": now.isoformat()})
        claim.stato_substati = kept
        metadata = VideoInspectionWorkflowService._metadata(claim)
        metadata["video_inspection_assignment"] = {
            "assigned_expert_id": expert.id,
            "assigned_expert_name": expert.full_name,
            "starts_at": starts_at.isoformat(),
            "ends_at": ends_at.isoformat(),
            "assigned_at": now.isoformat(),
        }
        claim.metadata_json = metadata
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                event_type="video_inspection_appointment_confirmed",
                event_time=now,
                source="video_inspection_automation",
                data_json={"expert_name": expert.full_name, "starts_at": starts_at.isoformat(), "ends_at": ends_at.isoformat()},
            )
        )
        appointment = starts_at.astimezone(LOCAL_TIMEZONE).strftime("%d/%m/%Y alle %H:%M")
        await InsuredNotificationService.notify(
            db, claim,
            kind="video_inspection_da_eseguire",
            title="Videoperizia oggi: tutto pronto",
            body=(
                f"La videoperizia è confermata per il {appointment}. "
                f"Il perito incaricato è {expert.full_name}. "
                "Apri il portale per le indicazioni prima della chiamata."
            ),
            deeplink=build_portal_deeplink(claim, "videoperizia"),
        )

    @staticmethod
    async def run_due_automation_cycle(db: AsyncSession) -> None:
        tenants = (await db.execute(select(Tenant))).scalars().all()
        local_now = datetime.now(LOCAL_TIMEZONE)
        for tenant in tenants:
            try:
                await VideoInspectionWorkflowService.run_due_assignments(db, tenant, local_now)
            except Exception:
                logger.exception("Video inspection automation failed for tenant %s", tenant.id)
                await db.rollback()


class VideoInspectionAutomationRuntime:
    _task: Optional[asyncio.Task] = None
    _stop_event: Optional[asyncio.Event] = None

    @classmethod
    async def start(cls) -> None:
        if cls._task is not None:
            return
        cls._stop_event = asyncio.Event()
        cls._task = asyncio.create_task(cls._runner(), name="video-inspection-automation-runtime")

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
                    await VideoInspectionWorkflowService.run_due_automation_cycle(session)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Video inspection automation runtime loop failed")
            try:
                await asyncio.wait_for(cls._stop_event.wait(), timeout=60)
            except asyncio.TimeoutError:
                continue
