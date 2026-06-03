"""
Central resolver for Telefono / Comunicazioni destinations.

The UI must not choose Telnyx/Twilio/Vonage or LiveKit directly. It sends the
abstract destination to PerX; this resolver selects the transport contract.
"""
from __future__ import annotations

import re

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.claim import Claim
from app.models.user import User
from app.schemas.communication import (
    CommunicationContext,
    CommunicationDestination,
    CommunicationDestinationType,
    CommunicationResolutionResponse,
    CommunicationTransport,
)
from app.services.communication_extension_service import CommunicationExtensionService


PHONE_RE = re.compile(r"^\+?[0-9][0-9\s().-]{5,20}$")
E164_RE = re.compile(r"^\+[1-9]\d{7,14}$")
EXTENSION_RE = re.compile(r"^\d{3}$")


class CommunicationDestinationResolver:
    async def resolve(
        self,
        db: AsyncSession,
        tenant_id: str,
        raw_destination: str,
        context: CommunicationContext | None = None,
    ) -> CommunicationResolutionResponse:
        context = context or CommunicationContext()
        value = raw_destination.strip()
        if not value:
            return CommunicationResolutionResponse()

        candidates: list[CommunicationDestination] = []
        claim_id = context.claim_id or await self._claim_id_for_reference(db, tenant_id, context.claim_reference)

        if EXTENSION_RE.match(value):
            user = await CommunicationExtensionService.find_user_by_extension(db, tenant_id, value)
            if user:
                candidates.append(self._destination(
                    destination_type=CommunicationDestinationType.internal_extension,
                    transport=CommunicationTransport.livekit,
                    target_id=user.id,
                    display_name=user.extension_display_name or user.full_name,
                    tenant_id=tenant_id,
                    raw_value=value,
                    context_claim_id=claim_id,
                ))

        user_matches = await self._matching_users(db, tenant_id, value)
        for user in user_matches:
            candidates.append(self._destination(
                destination_type=CommunicationDestinationType.internal_user,
                transport=CommunicationTransport.livekit,
                target_id=user.id,
                display_name=user.full_name,
                tenant_id=tenant_id,
                raw_value=value,
                context_claim_id=claim_id,
            ))

        if value.lower().startswith("team:"):
            candidates.append(self._destination(
                destination_type=CommunicationDestinationType.internal_team,
                transport=CommunicationTransport.routing_engine,
                target_id=value.split(":", 1)[1],
                display_name=value.split(":", 1)[1].replace("-", " ").title(),
                tenant_id=tenant_id,
                raw_value=value,
                context_claim_id=claim_id,
            ))

        if value.lower().startswith("queue:") or value.lower().startswith("coda:"):
            queue_id = value.split(":", 1)[1]
            candidates.append(self._destination(
                destination_type=CommunicationDestinationType.queue,
                transport=CommunicationTransport.routing_engine,
                target_id=queue_id,
                display_name=queue_id.replace("-", " ").title(),
                tenant_id=tenant_id,
                raw_value=value,
                context_claim_id=claim_id,
            ))

        if self._looks_like_guest_link(value):
            candidates.append(self._destination(
                destination_type=CommunicationDestinationType.external_guest_link,
                transport=CommunicationTransport.livekit,
                target_id=value,
                display_name="Ospite esterno via link",
                tenant_id=tenant_id,
                raw_value=value,
                context_claim_id=claim_id,
            ))

        if self._looks_like_phone(value):
            candidates.append(self._destination(
                destination_type=CommunicationDestinationType.external_phone,
                transport=CommunicationTransport.telecom_provider,
                target_id=self._normalize_phone(value),
                display_name=value,
                tenant_id=tenant_id,
                raw_value=value,
                context_claim_id=claim_id,
            ))

        # TODO(inter-tenant): add authorized cross-tenant PerX lookup here. Do not
        # expose users, rooms, or audit records across tenants without an explicit
        # invitation/permission grant.

        candidates = self._dedupe(candidates)
        return CommunicationResolutionResponse(
            selected=candidates[0] if len(candidates) == 1 else None,
            candidates=candidates,
            is_ambiguous=len(candidates) > 1,
        )

    def _destination(
        self,
        destination_type: CommunicationDestinationType,
        transport: CommunicationTransport,
        target_id: str | None,
        display_name: str,
        tenant_id: str,
        raw_value: str,
        context_claim_id: str | None,
    ) -> CommunicationDestination:
        return CommunicationDestination(
            destination_type=destination_type,
            transport=transport,
            target_id=target_id,
            display_name=display_name,
            tenant_id=tenant_id,
            suggested_caller_id=None,
            context_claim_id=context_claim_id,
            raw_value=raw_value,
        )

    async def _matching_users(self, db: AsyncSession, tenant_id: str, value: str) -> list[User]:
        if len(value) < 2:
            return []
        pattern = f"%{value}%"
        result = await db.execute(
            select(User)
            .where(
                User.tenant_id == tenant_id,
                User.is_active == True,
                or_(
                    User.full_name.ilike(pattern),
                    User.email.ilike(pattern),
                    User.personal_email.ilike(pattern),
                    User.professional_email.ilike(pattern),
                ),
            )
            .limit(8)
        )
        return list(result.scalars().all())

    async def _claim_id_for_reference(
        self,
        db: AsyncSession,
        tenant_id: str,
        claim_reference: str | None,
    ) -> str | None:
        if not claim_reference:
            return None
        reference = claim_reference.strip()
        if not reference:
            return None
        result = await db.execute(
            select(Claim.id)
            .where(
                Claim.tenant_id == tenant_id,
                or_(Claim.external_ref == reference, Claim.numero_sinistro == reference),
            )
            .limit(1)
        )
        return result.scalar_one_or_none()

    def _looks_like_phone(self, value: str) -> bool:
        compact = self._normalize_phone(value)
        return bool(E164_RE.match(compact) or PHONE_RE.match(value)) and not EXTENSION_RE.match(value)

    def _normalize_phone(self, value: str) -> str:
        return re.sub(r"[\s().-]", "", value)

    def _looks_like_guest_link(self, value: str) -> bool:
        lower = value.lower()
        return lower.startswith("http") and ("guest" in lower or "invite" in lower or "livekit" in lower)

    def _dedupe(self, destinations: list[CommunicationDestination]) -> list[CommunicationDestination]:
        seen: set[tuple[str, str | None, str]] = set()
        unique: list[CommunicationDestination] = []
        for destination in destinations:
            key = (destination.destination_type.value, destination.target_id, destination.raw_value)
            if key in seen:
                continue
            seen.add(key)
            unique.append(destination)
        return unique
