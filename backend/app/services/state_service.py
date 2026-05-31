"""
State service - manages claim state transitions and substati (tag list).
"""
from __future__ import annotations

import uuid
from datetime import datetime
from typing import Iterable, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.claim_status import (
    ClaimStatus,
    ISTRUZIONE_REQUIRED_FIELDS,
    SubstatoSource,
    VALID_TRANSITIONS,
    is_valid_transition,
)
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.claim_state import ClaimState


# Sopralluogo substato names produced by the inspection workflow.
SOPRALLUOGO_AUTO_SUBSTATI = {"da_fissare", "fissato", "confermato", "da_concordare", "da_rifissare"}


def can_exit_istruzione(claim: Claim) -> tuple[bool, list[str]]:
    missing = [f for f in ISTRUZIONE_REQUIRED_FIELDS if not getattr(claim, f, None)]
    return (not missing, missing)


def has_substato(claim: Claim, tag: str) -> bool:
    return any(s.get("tag") == tag for s in (claim.stato_substati or []))


def primary_substato(claim: Claim) -> str | None:
    items = claim.stato_substati or []
    return items[0].get("tag") if items else None


class StateService:
    @staticmethod
    def _now_iso() -> str:
        return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

    @staticmethod
    def _normalize_tag(tag: str) -> str:
        return tag.strip().lower().replace(" ", "_")

    @staticmethod
    def _parse_iso_datetime(raw_value: str | None):
        if not raw_value:
            return None
        candidate = raw_value.strip()
        if candidate.endswith("Z"):
            candidate = candidate[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(candidate)
        except ValueError:
            return None

    @staticmethod
    def _substati_list(claim: Claim) -> list[dict]:
        return list(claim.stato_substati or [])

    @staticmethod
    async def _load_claim(db: AsyncSession, tenant_id: str, claim_id: str) -> Claim | None:
        result = await db.execute(
            select(Claim).where((Claim.id == claim_id) & (Claim.tenant_id == tenant_id))
        )
        return result.scalar_one_or_none()

    @staticmethod
    def _emit_substato_event(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        user_id: Optional[str],
        old_list: list[dict],
        new_list: list[dict],
        source: SubstatoSource,
    ) -> None:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim_id,
                event_type="substato_changed",
                actor_user_id=user_id,
                data_json={
                    "from": [s.get("tag") for s in old_list],
                    "to": [s.get("tag") for s in new_list],
                    "source": source,
                },
                source="manual" if source == "user" else source,
            )
        )

    @staticmethod
    async def set_substati(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        tags: list[str],
        *,
        source: SubstatoSource,
        user_id: Optional[str] = None,
        commit: bool = True,
    ) -> bool:
        claim = await StateService._load_claim(db, tenant_id, claim_id)
        if not claim:
            return False
        now = StateService._now_iso()
        seen: set[str] = set()
        new_list: list[dict] = []
        for raw in tags:
            tag = StateService._normalize_tag(raw)
            if not tag or tag in seen:
                continue
            seen.add(tag)
            new_list.append({"tag": tag, "source": source, "added_at": now})
        old_list = StateService._substati_list(claim)
        claim.stato_substati = new_list
        claim.updated_at = datetime.utcnow()
        StateService._emit_substato_event(db, tenant_id, claim_id, user_id, old_list, new_list, source)
        if commit:
            await db.commit()
        return True

    @staticmethod
    async def add_substato(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        tag: str,
        *,
        source: SubstatoSource,
        user_id: Optional[str] = None,
        commit: bool = True,
    ) -> bool:
        claim = await StateService._load_claim(db, tenant_id, claim_id)
        if not claim:
            return False
        normalized = StateService._normalize_tag(tag)
        if not normalized:
            return False
        current = StateService._substati_list(claim)
        if any(s.get("tag") == normalized for s in current):
            return True
        old_list = list(current)
        current.append({"tag": normalized, "source": source, "added_at": StateService._now_iso()})
        claim.stato_substati = current
        claim.updated_at = datetime.utcnow()
        StateService._emit_substato_event(db, tenant_id, claim_id, user_id, old_list, current, source)
        if commit:
            await db.commit()
        return True

    @staticmethod
    async def remove_substato(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        tag: str,
        *,
        source: SubstatoSource,
        user_id: Optional[str] = None,
        commit: bool = True,
    ) -> bool:
        claim = await StateService._load_claim(db, tenant_id, claim_id)
        if not claim:
            return False
        normalized = StateService._normalize_tag(tag)
        current = StateService._substati_list(claim)
        new_list = [s for s in current if s.get("tag") != normalized]
        if len(new_list) == len(current):
            return True
        claim.stato_substati = new_list
        claim.updated_at = datetime.utcnow()
        StateService._emit_substato_event(db, tenant_id, claim_id, user_id, current, new_list, source)
        if commit:
            await db.commit()
        return True

    @staticmethod
    async def transition_state(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        from_state: Optional[str],
        to_state: str,
        user_id: Optional[str],
        reason: Optional[str] = None,
        payload: Optional[dict] = None,
        *,
        commit: bool = True,
        event_source: str = "manual",
        sopralluogo_substato: Optional[str] = None,
    ) -> bool:
        """Transition claim to new state with validation."""
        claim = await StateService._load_claim(db, tenant_id, claim_id)
        if not claim:
            return False

        current_state = claim.stato_corrente
        if from_state and current_state != from_state:
            return False
        if not is_valid_transition(current_state, to_state):
            return False

        # Gate: exiting ISTRUZIONE requires the anagrafica/polizza fields.
        if current_state == ClaimStatus.ISTRUZIONE.value and to_state != ClaimStatus.ISTRUZIONE.value:
            ok, _missing = can_exit_istruzione(claim)
            if not ok:
                await StateService.add_substato(
                    db, tenant_id, claim_id, "dati_incompleti",
                    source="system", user_id=user_id, commit=False,
                )
                return False

        old_state = claim.stato_corrente
        claim.stato_corrente = to_state

        now = datetime.utcnow()
        if to_state in (ClaimStatus.ATTO_INVIATO.value, ClaimStatus.ESITO_COMUNICATO.value):
            claim.data_invio_atto = now
        elif to_state == ClaimStatus.CHIUSA.value and not claim.closed_at:
            claim.closed_at = now
        elif to_state in (
            ClaimStatus.DA_GESTIRE_TRADIZIONALE.value,
            ClaimStatus.DA_GESTIRE_DOCUMENTALE.value,
            ClaimStatus.DA_GESTIRE_VIDEO.value,
            ClaimStatus.IN_GESTIONE.value,
        ):
            if not claim.data_assegnazione:
                claim.data_assegnazione = now

        scheduled_at = StateService._parse_iso_datetime((payload or {}).get("scheduled_at"))
        if to_state == ClaimStatus.SOPRALLUOGO.value:
            claim.sopralluogo = True
            kept = [s for s in StateService._substati_list(claim) if s.get("tag") not in SOPRALLUOGO_AUTO_SUBSTATI]
            seed_tag = sopralluogo_substato or "da_fissare"
            kept.append({
                "tag": seed_tag,
                "source": "system",
                "added_at": StateService._now_iso(),
            })
            claim.stato_substati = kept
            if seed_tag == "fissato" and scheduled_at:
                claim.data_sopralluogo = scheduled_at
            elif seed_tag == "da_fissare":
                claim.data_sopralluogo = None
        elif old_state == ClaimStatus.SOPRALLUOGO.value:
            claim.stato_substati = [
                s for s in StateService._substati_list(claim)
                if s.get("tag") not in SOPRALLUOGO_AUTO_SUBSTATI
            ]

        claim.version += 1
        claim.updated_at = now

        db.add(ClaimState(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            from_state=old_state,
            to_state=to_state,
            changed_by_user_id=user_id,
            reason=reason,
            payload_json=payload,
        ))
        db.add(ClaimEvent(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            event_type="state_changed",
            actor_user_id=user_id,
            data_json={"from": old_state, "to": to_state, "reason": reason},
            source=event_source,
        ))

        if to_state == ClaimStatus.SOPRALLUOGO.value and (sopralluogo_substato or "da_fissare") == "da_fissare":
            db.add(ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim_id,
                event_type="inspection_scheduling_requested",
                actor_user_id=user_id,
                data_json={"address_line": claim.indirizzo_assicurato},
                source=event_source,
            ))

        if event_source != "automation":
            from app.core.config import settings
            if settings.FF_AUTOMATIONS_ENABLED:
                from app.services.automation_service import AutomationService
                await AutomationService.handle_state_change(db, tenant_id, claim_id, to_state)

        # Generazione task da transizione (migrata dal client TaskGenerationService).
        # Eseguita sempre, non gated da FF_AUTOMATIONS_ENABLED: sono task di
        # business, non automazioni opzionali.
        from app.services.automation_service import AutomationService as _AS
        await _AS.generate_transition_tasks(db, claim, old_state, to_state, user_id)

        if commit:
            await db.commit()
        return True


def allowed_next_states(current: str) -> Iterable[str]:
    return VALID_TRANSITIONS.get(current, set())
