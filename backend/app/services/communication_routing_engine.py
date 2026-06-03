"""
PerX-owned communication routing engine.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.claim import Claim
from app.models.communication import CallQueue


@dataclass(frozen=True)
class RoutingDecision:
    action: str
    target_type: str | None = None
    target_id: str | None = None
    state: str = "pending"
    reason: str | None = None
    metadata: dict[str, Any] | None = None


class CommunicationRoutingEngine:
    async def route_inbound_call(
        self,
        db: AsyncSession,
        tenant_id: str,
        from_value: str | None,
        to_value: str | None,
    ) -> RoutingDecision:
        claims = await self._claims_for_phone(db, tenant_id, from_value)
        if len(claims) == 1:
            claim = claims[0]
            assigned_user = claim.owner_email
            if assigned_user:
                return RoutingDecision(
                    action="ring_user",
                    target_type="user_email",
                    target_id=assigned_user,
                    state="ringing",
                    reason="caller_matched_open_claim",
                    metadata={"claim_id": claim.id},
                )
            queue = await self._default_queue(db, tenant_id)
            return RoutingDecision(
                action="enqueue",
                target_type="queue",
                target_id=queue.id if queue else "triage",
                state="ringing",
                reason="claim_without_assigned_user",
                metadata={"claim_id": claim.id},
            )
        if len(claims) > 1:
            return RoutingDecision(
                action="triage",
                target_type="ai_or_queue",
                target_id="needs_triage",
                state="needs_triage",
                reason="caller_matched_multiple_claims",
                metadata={"claim_ids": [claim.id for claim in claims]},
            )
        queue = await self._default_queue(db, tenant_id)
        return RoutingDecision(
            action="triage",
            target_type="queue",
            target_id=queue.id if queue else "triage",
            state="needs_triage",
            reason="unknown_caller",
            metadata={},
        )

    async def _claims_for_phone(self, db: AsyncSession, tenant_id: str, phone: str | None) -> list[Claim]:
        if not phone:
            return []
        compact = self._compact_phone(phone)
        pattern = f"%{compact[-8:]}%" if len(compact) >= 8 else f"%{compact}%"
        result = await db.execute(
            select(Claim)
            .where(
                Claim.tenant_id == tenant_id,
                or_(
                    Claim.telefono_assicurato.ilike(pattern),
                    Claim.telefono_contraente.ilike(pattern),
                    Claim.telefono_danneggiato.ilike(pattern),
                    Claim.telefono_agenzia.ilike(pattern),
                ),
            )
            .limit(5)
        )
        return list(result.scalars().all())

    async def _default_queue(self, db: AsyncSession, tenant_id: str) -> CallQueue | None:
        result = await db.execute(
            select(CallQueue).where(
                CallQueue.tenant_id == tenant_id,
                CallQueue.enabled == True,
                CallQueue.slug == "triage",
            )
        )
        return result.scalar_one_or_none()

    def _compact_phone(self, phone: str) -> str:
        return "".join(ch for ch in phone if ch.isdigit() or ch == "+")
