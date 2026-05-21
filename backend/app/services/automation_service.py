"""
Server-side automations migrated from the legacy client trigger services.
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.automation import AutomationTriggerState
from app.models.case_task import CaseTask
from app.models.claim import Claim
from app.models.claim_diary_entry import ClaimDiaryEntry
from app.models.claim_event import ClaimEvent
from app.models.tenant import Tenant
from app.models.user import User
from app.services.process_job_service import ProcessJobService
from app.services.state_service import StateService

logger = logging.getLogger(__name__)


class PassiveTriggerType:
    ATTO_INVIATO = "atto_inviato"
    ATTO_FOLLOWUP = "atto_followup"
    DOCUMENTAZIONE_RICHIESTA = "documentazione_richiesta"
    VIDEOPERIZIA_RICHIESTA = "videoperizia_richiesta"


POST_ATTO_STATES = {"SV032", "SV033", "SV090", "SI001", "SI002"}
GESTIONE_STATES = {"SV012", "SV011", "SV013", "SV020", "SV021"}


@dataclass(frozen=True)
class QuickTransition:
    to_state: str
    detail_if_missing_folder: bool = True


class AutomationService:
    @staticmethod
    def _now() -> datetime:
        return datetime.now(timezone.utc)

    @staticmethod
    def _days_since(value: datetime) -> int:
        base = value
        if base.tzinfo is None:
            base = base.replace(tzinfo=timezone.utc)
        return (AutomationService._now() - base.astimezone(timezone.utc)).days

    @staticmethod
    def _text(entry: ClaimDiaryEntry) -> str:
        return ((entry.body_text or "") + "\n" + (entry.title or "")).lower()

    @staticmethod
    def _entry_main_text(entry: ClaimDiaryEntry) -> str:
        return (entry.body_text or entry.title or "").lower()

    @staticmethod
    def _metadata(entry: ClaimDiaryEntry) -> dict:
        return dict(entry.metadata_json or {})

    @staticmethod
    def _has_attachments(entry: ClaimDiaryEntry) -> bool:
        metadata = AutomationService._metadata(entry)
        attachments = metadata.get("attachments") or metadata.get("attachment_types") or []
        if isinstance(attachments, list) and attachments:
            return True
        return bool(metadata.get("has_attachments"))

    @staticmethod
    def _attachment_types(entry: ClaimDiaryEntry) -> list[str]:
        metadata = AutomationService._metadata(entry)
        raw = metadata.get("attachment_types") or metadata.get("attachments") or []
        if not isinstance(raw, list):
            return []
        values: list[str] = []
        for item in raw:
            if isinstance(item, str):
                values.append(item)
            elif isinstance(item, dict):
                values.append(str(item.get("filename") or item.get("name") or item.get("type") or ""))
        return values

    @staticmethod
    def _is_communication(entry: ClaimDiaryEntry) -> bool:
        entry_type = (entry.entry_type or "").lower()
        metadata = AutomationService._metadata(entry)
        return (
            entry_type in {"email", "mail", "whatsapp", "wa"}
            or bool(metadata.get("email_message_id"))
            or bool(metadata.get("whatsapp_chat_id"))
            or bool(metadata.get("whatsapp_message_ids"))
        )

    @staticmethod
    def _is_outgoing(entry: ClaimDiaryEntry) -> bool:
        entry_type = (entry.entry_type or "").lower()
        metadata = AutomationService._metadata(entry)
        if entry_type in {"system", "sistema"}:
            return True
        direction = str(metadata.get("direction") or metadata.get("message_direction") or "").lower()
        if direction in {"out", "outbound", "sent", "uscita"}:
            return True
        if direction in {"in", "inbound", "received", "entrata"}:
            return False
        return not bool(metadata.get("email_message_id") or metadata.get("message_id") or metadata.get("whatsapp_message_ids"))

    @staticmethod
    def _claim_has_folder(claim: Claim) -> bool:
        metadata = dict(claim.metadata_json or {})
        return bool(claim.cartella or metadata.get("folder_path") or metadata.get("has_folder"))

    @staticmethod
    def _quick_transition_for(entry: ClaimDiaryEntry) -> Optional[QuickTransition]:
        subject = (entry.title or "").lower()
        body = (entry.body_text or "").lower()
        has_attachments = AutomationService._has_attachments(entry)
        attachment_types = [value.lower() for value in AutomationService._attachment_types(entry)]

        if "richiesta documentazione" in subject:
            return QuickTransition("SV002")
        if has_attachments and ("documentaz" in subject or "documentaz" in body):
            return QuickTransition("SV010")
        if "perizia controllata" in subject:
            return QuickTransition("SV041", detail_if_missing_folder=False)
        if "richiesta revisione" in subject:
            return QuickTransition("SV091")
        if "sopralluogo fissato" in subject:
            return QuickTransition("SV050")
        if "sopralluogo restituito" in subject:
            return QuickTransition("SV051")
        if "videoperizia" in subject and ("fissata" in subject or "concordata" in body):
            return QuickTransition("SV014")
        if "invio atto" in subject or "atto da firmare" in subject:
            return QuickTransition("SV031")
        if has_attachments and any("atto" in value for value in attachment_types):
            return QuickTransition("SV032")

        acceptance_patterns = [
            "accetto l'importo",
            "accettiamo l'importo",
            "accetto senza atto",
            "accettiamo senza atto",
            "accetto verbalmente",
            "accettiamo verbalmente",
            "accetto senza firmare",
            "accettiamo senza firmare",
            "accetto l'importo proposto",
            "accettiamo l'importo proposto",
            "accetto la liquidazione",
            "accettiamo la liquidazione",
            "accetto la stima",
            "accettiamo la stima",
        ]
        if any(pattern in body or pattern in subject for pattern in acceptance_patterns):
            if not has_attachments or not any("atto" in value for value in attachment_types):
                return QuickTransition("SV033")

        if "esito" in subject and not has_attachments:
            return QuickTransition("SV030")
        return None

    @staticmethod
    async def process_diary_entry(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        entry: ClaimDiaryEntry,
        user_id: Optional[str],
    ) -> None:
        if not settings.FF_AUTOMATIONS_ENABLED:
            return

        await AutomationService.apply_quick_state_transition(db, tenant_id, claim, entry, user_id)
        await AutomationService.enqueue_local_ai_analysis(db, tenant_id, claim, entry, user_id)
        await AutomationService.check_claim_passive_triggers(db, claim)
        await db.commit()

    @staticmethod
    async def apply_quick_state_transition(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        entry: ClaimDiaryEntry,
        user_id: Optional[str],
    ) -> None:
        transition = AutomationService._quick_transition_for(entry)
        if transition is None:
            return
        if claim.stato_corrente == "SV090" and transition.to_state != "SV091":
            return

        payload: dict = {"source_diary_entry_id": entry.id}
        if transition.detail_if_missing_folder and not AutomationService._claim_has_folder(claim):
            payload["stato_detail"] = "da scaricare"

        success = await StateService.transition_state(
            db,
            tenant_id,
            claim.id,
            claim.stato_corrente,
            transition.to_state,
            user_id,
            "Automazione da comunicazione",
            payload,
            commit=False,
            event_source="automation",
        )
        if success:
            await AutomationService.handle_state_change(db, tenant_id, claim.id, transition.to_state)

    @staticmethod
    async def enqueue_local_ai_analysis(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        entry: ClaimDiaryEntry,
        user_id: Optional[str],
    ) -> None:
        if not settings.FF_LOCAL_AI_PROCESS_JOBS_ENABLED:
            return
        if not AutomationService._is_communication(entry) and not AutomationService._has_attachments(entry):
            return

        text = (entry.body_text or entry.title or "").strip()
        metadata = AutomationService._metadata(entry)
        if not text and not metadata:
            return

        await ProcessJobService.enqueue(
            db,
            tenant_id=tenant_id,
            claim_id=claim.id,
            created_by_user_id=user_id,
            job_type="local_ai.diary_entry_analysis",
            priority=AutomationService._task_priority(claim),
            idempotency_key=f"local_ai.diary_entry_analysis:{tenant_id}:{entry.id}",
            input_json={
                "claimId": claim.id,
                "claimRef": claim.external_ref,
                "diaryEntryId": entry.id,
                "entryType": entry.entry_type,
                "title": entry.title,
                "bodyText": entry.body_text,
                "happenedAt": entry.happened_at.isoformat() if entry.happened_at else None,
                "metadata": metadata,
                "requestedOutputs": [
                    "summary",
                    "classification",
                    "suggested_state",
                    "suggested_tasks",
                    "extracted_entities",
                ],
            },
            tags_json={"source": "automation", "kind": "local_ai", "entity": "diary_entry"},
        )

    @staticmethod
    async def handle_state_change(db: AsyncSession, tenant_id: str, claim_id: str, new_state: str) -> None:
        if new_state in {"SV032", "SV033", "SV090"}:
            await AutomationService.deactivate_trigger(db, tenant_id, claim_id, PassiveTriggerType.ATTO_INVIATO)
            await AutomationService.deactivate_trigger(db, tenant_id, claim_id, PassiveTriggerType.ATTO_FOLLOWUP)
        if new_state in GESTIONE_STATES:
            await AutomationService.deactivate_trigger(db, tenant_id, claim_id, PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA)
        if new_state == "SV014":
            await AutomationService.deactivate_trigger(db, tenant_id, claim_id, PassiveTriggerType.VIDEOPERIZIA_RICHIESTA)

    @staticmethod
    async def run_due_automation_cycle(db: AsyncSession) -> None:
        if not settings.FF_AUTOMATIONS_ENABLED:
            return

        tenants = (await db.execute(select(Tenant))).scalars().all()
        for tenant in tenants:
            try:
                claims = (
                    await db.execute(
                        select(Claim).where(
                            Claim.tenant_id == tenant.id,
                            Claim.stato_corrente != "SV090",
                        )
                    )
                ).scalars().all()
                for claim in claims:
                    await AutomationService.check_claim_passive_triggers(db, claim)
                await db.commit()
            except Exception:
                logger.exception("Automation cycle failed for tenant %s", tenant.id)
                await db.rollback()

    @staticmethod
    async def check_claim_passive_triggers(db: AsyncSession, claim: Claim) -> None:
        entries = (
            await db.execute(
                select(ClaimDiaryEntry)
                .where(
                    ClaimDiaryEntry.tenant_id == claim.tenant_id,
                    ClaimDiaryEntry.claim_id == claim.id,
                )
                .order_by(ClaimDiaryEntry.happened_at.asc())
            )
        ).scalars().all()

        has_active_contestation = AutomationService._has_active_contestation(entries)
        await AutomationService._check_atto_inviato(db, claim, entries, has_active_contestation)
        await AutomationService._check_atto_followup(db, claim, entries, has_active_contestation)
        await AutomationService._check_documentazione_richiesta(db, claim, entries)
        await AutomationService._check_videoperizia_richiesta(db, claim, entries)

    @staticmethod
    async def _check_atto_inviato(
        db: AsyncSession,
        claim: Claim,
        entries: list[ClaimDiaryEntry],
        has_active_contestation: bool,
    ) -> None:
        if claim.stato_corrente in POST_ATTO_STATES:
            return

        atto_entry = next(
            (
                entry
                for entry in reversed(entries)
                if "atto inviato" in AutomationService._entry_main_text(entry)
                or "atto da inviare" in AutomationService._entry_main_text(entry)
            ),
            None,
        )
        if atto_entry is None:
            return

        days_since = AutomationService._days_since(atto_entry.happened_at)
        if days_since < 7:
            return

        has_response = any(
            entry.happened_at > atto_entry.happened_at
            and AutomationService._is_communication(entry)
            and not AutomationService._is_outgoing(entry)
            for entry in entries
        )
        if has_response:
            await AutomationService.deactivate_trigger(db, claim.tenant_id, claim.id, PassiveTriggerType.ATTO_INVIATO)
            return
        if has_active_contestation:
            return

        if await AutomationService._active_trigger_exists(db, claim.id, PassiveTriggerType.ATTO_INVIATO):
            return

        await AutomationService._generate_followup_task(
            db,
            claim,
            PassiveTriggerType.ATTO_INVIATO,
            days_since,
            AutomationService._atto_followup_draft(claim),
        )
        await AutomationService.save_trigger_state(db, claim, PassiveTriggerType.ATTO_INVIATO, atto_entry.happened_at)

    @staticmethod
    async def _check_atto_followup(
        db: AsyncSession,
        claim: Claim,
        entries: list[ClaimDiaryEntry],
        has_active_contestation: bool,
    ) -> None:
        if claim.stato_corrente in POST_ATTO_STATES:
            return

        tasks = (
            await db.execute(
                select(CaseTask)
                .where(
                    CaseTask.tenant_id == claim.tenant_id,
                    CaseTask.claim_id == claim.id,
                    CaseTask.title.contains("Restiamo in attesa"),
                    CaseTask.status == "done",
                )
            )
        ).scalars().all()
        if not tasks:
            return

        dated_tasks = [
            (task.completed_at or task.due_date, task)
            for task in tasks
            if task.completed_at is not None or task.due_date is not None
        ]
        if not dated_tasks:
            return
        task_date, _ = sorted(dated_tasks, key=lambda item: item[0], reverse=True)[0]
        days_since = AutomationService._days_since(task_date)
        if days_since < 7:
            return

        has_response = any(
            entry.happened_at > task_date
            and AutomationService._is_communication(entry)
            and not AutomationService._is_outgoing(entry)
            for entry in entries
        )
        if has_response or has_active_contestation:
            return

        await AutomationService._generate_close_non_concordato_task(db, claim)

    @staticmethod
    async def _check_documentazione_richiesta(
        db: AsyncSession,
        claim: Claim,
        entries: list[ClaimDiaryEntry],
    ) -> None:
        doc_entry = next(
            (
                entry
                for entry in reversed(entries)
                if (
                    "documentazione" in AutomationService._entry_main_text(entry)
                    or "foto" in AutomationService._entry_main_text(entry)
                    or "allegat" in AutomationService._entry_main_text(entry)
                )
                and (
                    "richied" in AutomationService._entry_main_text(entry)
                    or "inviat" in AutomationService._entry_main_text(entry)
                    or "necessari" in AutomationService._entry_main_text(entry)
                )
            ),
            None,
        )
        if doc_entry is None:
            return

        days_since = AutomationService._days_since(doc_entry.happened_at)
        if days_since < 5:
            return

        has_documentation_response = any(
            entry.happened_at > doc_entry.happened_at
            and AutomationService._is_communication(entry)
            and "allegat" in (entry.body_text or "").lower()
            for entry in entries
        )
        if has_documentation_response:
            return
        if await AutomationService._active_trigger_exists(db, claim.id, PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA):
            return

        await AutomationService._generate_followup_task(
            db,
            claim,
            PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA,
            days_since,
            AutomationService._documentazione_followup_draft(claim),
        )
        await AutomationService.save_trigger_state(db, claim, PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA, doc_entry.happened_at)

    @staticmethod
    async def _check_videoperizia_richiesta(
        db: AsyncSession,
        claim: Claim,
        entries: list[ClaimDiaryEntry],
    ) -> None:
        video_entry = next(
            (
                entry
                for entry in reversed(entries)
                if "videoperizia" in AutomationService._entry_main_text(entry)
                or "video perizia" in AutomationService._entry_main_text(entry)
            ),
            None,
        )
        if video_entry is None:
            return

        days_since = AutomationService._days_since(video_entry.happened_at)
        if days_since < 3:
            return

        has_response = any(
            entry.happened_at > video_entry.happened_at and AutomationService._is_communication(entry)
            for entry in entries
        )
        if has_response:
            return
        if await AutomationService._active_trigger_exists(db, claim.id, PassiveTriggerType.VIDEOPERIZIA_RICHIESTA):
            return

        await AutomationService._generate_followup_task(
            db,
            claim,
            PassiveTriggerType.VIDEOPERIZIA_RICHIESTA,
            days_since,
            AutomationService._videoperizia_followup_draft(claim),
        )
        await AutomationService.save_trigger_state(db, claim, PassiveTriggerType.VIDEOPERIZIA_RICHIESTA, video_entry.happened_at)

    @staticmethod
    def _has_active_contestation(entries: list[ClaimDiaryEntry]) -> bool:
        contestations = [
            entry
            for entry in entries
            if "contest" in AutomationService._entry_main_text(entry)
            or "non concord" in AutomationService._entry_main_text(entry)
            or "non accett" in AutomationService._entry_main_text(entry)
        ]
        if not contestations:
            return False
        last_contestation = sorted(contestations, key=lambda value: value.happened_at, reverse=True)[0]
        resolutions = [
            entry
            for entry in entries
            if entry.happened_at > last_contestation.happened_at
            and (
                "accordo" in AutomationService._entry_main_text(entry)
                or "risolto" in ((entry.title or "").lower())
                or "nuovo atto" in ((entry.title or "").lower())
            )
        ]
        return not resolutions

    @staticmethod
    async def _automation_user_id(db: AsyncSession, tenant_id: str) -> Optional[str]:
        user = (
            await db.execute(
                select(User)
                .where(User.tenant_id == tenant_id, User.is_active.is_(True))
                .order_by(User.created_at.asc())
                .limit(1)
            )
        ).scalar_one_or_none()
        return user.id if user else None

    @staticmethod
    def _task_priority(claim: Claim) -> int:
        if claim.priority is None:
            return 50
        if 0 <= claim.priority <= 1:
            return int(claim.priority * 100)
        return max(0, min(100, int(claim.priority)))

    @staticmethod
    async def _task_exists(db: AsyncSession, claim_id: str, trigger_type: str, title: str) -> bool:
        result = await db.execute(
            select(CaseTask).where(
                CaseTask.claim_id == claim_id,
                CaseTask.title == title,
                CaseTask.status != "cancelled",
            )
        )
        return any((task.metadata_json or {}).get("triggerType") == trigger_type for task in result.scalars().all())

    @staticmethod
    async def _generate_followup_task(
        db: AsyncSession,
        claim: Claim,
        trigger_type: str,
        days_since: int,
        draft_message: str,
    ) -> None:
        if trigger_type == PassiveTriggerType.ATTO_INVIATO:
            title = "Follow-up: Restiamo in attesa di atto"
            description = f"Sono passati {days_since} giorni dall'invio dell'atto senza risposta"
        elif trigger_type == PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA:
            title = "Follow-up: Richiesta documentazione"
            description = f"Sono passati {days_since} giorni dalla richiesta di documentazione"
        elif trigger_type == PassiveTriggerType.VIDEOPERIZIA_RICHIESTA:
            title = "Follow-up: Richiesta videoperizia"
            description = f"Sono passati {days_since} giorni dalla richiesta di videoperizia"
        else:
            title = "Follow-up"
            description = f"Sono passati {days_since} giorni"

        if await AutomationService._task_exists(db, claim.id, trigger_type, title):
            return

        user_id = await AutomationService._automation_user_id(db, claim.tenant_id)
        if user_id is None:
            logger.warning("No active user found for tenant %s; automation task skipped", claim.tenant_id)
            return

        db.add(
            CaseTask(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                title=title,
                description=description,
                status="open",
                created_by_user_id=user_id,
                due_date=AutomationService._now(),
                priority=AutomationService._task_priority(claim),
                type="aiGenerated",
                metadata_json={
                    "triggerType": trigger_type,
                    "draftMessage": draft_message,
                    "daysSince": days_since,
                },
            )
        )
        await AutomationService._create_event(db, claim, "task_created", {"title": title, "triggerType": trigger_type})

    @staticmethod
    async def _generate_close_non_concordato_task(db: AsyncSession, claim: Claim) -> None:
        trigger_type = PassiveTriggerType.ATTO_FOLLOWUP
        title = "Chiudere sinistro non concordato"
        if await AutomationService._task_exists(db, claim.id, trigger_type, title):
            return

        user_id = await AutomationService._automation_user_id(db, claim.tenant_id)
        if user_id is None:
            logger.warning("No active user found for tenant %s; automation task skipped", claim.tenant_id)
            return

        db.add(
            CaseTask(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                title=title,
                description="Sono passati più di 14 giorni dall'invio dell'atto senza risposta",
                status="open",
                created_by_user_id=user_id,
                due_date=AutomationService._now(),
                priority=AutomationService._task_priority(claim),
                type="aiGenerated",
                metadata_json={"triggerType": trigger_type},
            )
        )
        await AutomationService._create_event(db, claim, "task_created", {"title": title, "triggerType": trigger_type})

    @staticmethod
    async def _create_event(db: AsyncSession, claim: Claim, event_type: str, data: dict) -> None:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                event_type=event_type,
                actor_user_id=None,
                data_json=data,
                source="automation",
            )
        )

    @staticmethod
    def _atto_followup_draft(claim: Claim) -> str:
        return f"""Gentile Cliente,

in riferimento al sinistro {claim.external_ref or ""}, restiamo in attesa della restituzione dell'atto sottoscritto.

Restiamo a disposizione per qualsiasi chiarimento.

Cordiali saluti
"""

    @staticmethod
    def _documentazione_followup_draft(claim: Claim) -> str:
        return f"""Gentile Cliente,

in riferimento al sinistro {claim.external_ref or ""}, restiamo in attesa della documentazione richiesta.

Restiamo a disposizione per qualsiasi chiarimento.

Cordiali saluti
"""

    @staticmethod
    def _videoperizia_followup_draft(claim: Claim) -> str:
        return f"""Gentile Cliente,

in riferimento al sinistro {claim.external_ref or ""}, restiamo in attesa di conferma per la videoperizia richiesta.

Restiamo a disposizione per fissare un appuntamento.

Cordiali saluti
"""

    @staticmethod
    async def _active_trigger_exists(db: AsyncSession, claim_id: str, trigger_type: str) -> bool:
        state = (
            await db.execute(
                select(AutomationTriggerState).where(
                    AutomationTriggerState.claim_id == claim_id,
                    AutomationTriggerState.trigger_type == trigger_type,
                    AutomationTriggerState.is_active.is_(True),
                )
            )
        ).scalar_one_or_none()
        return state is not None

    @staticmethod
    async def save_trigger_state(
        db: AsyncSession,
        claim: Claim,
        trigger_type: str,
        start_date: datetime,
    ) -> None:
        timeout_days = {
            PassiveTriggerType.ATTO_INVIATO: 7,
            PassiveTriggerType.ATTO_FOLLOWUP: 7,
            PassiveTriggerType.DOCUMENTAZIONE_RICHIESTA: 5,
            PassiveTriggerType.VIDEOPERIZIA_RICHIESTA: 3,
        }[trigger_type]
        state = (
            await db.execute(
                select(AutomationTriggerState).where(
                    AutomationTriggerState.claim_id == claim.id,
                    AutomationTriggerState.trigger_type == trigger_type,
                )
            )
        ).scalar_one_or_none()
        if state is None:
            state = AutomationTriggerState(
                id=str(uuid.uuid4()),
                tenant_id=claim.tenant_id,
                claim_id=claim.id,
                trigger_type=trigger_type,
            )
            db.add(state)
        state.start_date = start_date
        state.is_active = True
        state.last_check_date = AutomationService._now()
        state.timeout_days = timeout_days

    @staticmethod
    async def deactivate_trigger(db: AsyncSession, tenant_id: str, claim_id: str, trigger_type: str) -> None:
        state = (
            await db.execute(
                select(AutomationTriggerState).where(
                    AutomationTriggerState.tenant_id == tenant_id,
                    AutomationTriggerState.claim_id == claim_id,
                    AutomationTriggerState.trigger_type == trigger_type,
                )
            )
        ).scalar_one_or_none()
        if state is not None:
            state.is_active = False
            state.last_check_date = AutomationService._now()


class AutomationRuntime:
    _task: Optional[asyncio.Task] = None
    _stop_event: Optional[asyncio.Event] = None

    @classmethod
    async def start(cls) -> None:
        if not settings.FF_AUTOMATIONS_ENABLED or cls._task is not None:
            return
        cls._stop_event = asyncio.Event()
        cls._task = asyncio.create_task(cls._runner(), name="perx-automation-runtime")

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
                    await AutomationService.run_due_automation_cycle(session)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Automation runtime loop failed")

            try:
                await asyncio.wait_for(
                    cls._stop_event.wait(),
                    timeout=max(10, settings.AUTOMATION_POLL_SECONDS),
                )
            except asyncio.TimeoutError:
                continue
