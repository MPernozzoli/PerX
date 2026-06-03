"""
Caller/contact enrichment for the unified communication module.

Routing decides where a call goes. This resolver decides how the caller should
be presented to users, using tenant-local claims and rubrica records.
"""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.claim import Claim
from app.models.rubrica import RubricaAgente, RubricaAgenzia, RubricaLiquidatore
from app.schemas.communication import CommunicationCallerContext, CommunicationClaimContext


@dataclass(frozen=True)
class MatchedPhoneField:
    role: str
    phone: str | None
    display_name: str | None


class CommunicationContactResolver:
    async def resolve_caller(
        self,
        db: AsyncSession,
        tenant_id: str,
        phone_number: str | None,
    ) -> CommunicationCallerContext | None:
        if not phone_number:
            return None

        compact = self._compact_phone(phone_number)
        if not compact:
            return None

        claim_context = await self._claim_context_for_phone(db, tenant_id, compact, phone_number)
        rubrica_context = await self._rubrica_context_for_phone(db, tenant_id, compact, phone_number)

        if claim_context and rubrica_context:
            return rubrica_context.model_copy(update={"claim_context": claim_context.claim_context})
        if claim_context:
            return claim_context
        return rubrica_context

    async def _claim_context_for_phone(
        self,
        db: AsyncSession,
        tenant_id: str,
        compact: str,
        raw_phone: str,
    ) -> CommunicationCallerContext | None:
        pattern = self._phone_pattern(compact)
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
            .order_by(Claim.updated_at.desc())
            .limit(1)
        )
        claim = result.scalar_one_or_none()
        if claim is None:
            return None

        match = self._matched_claim_phone(claim, compact)
        claim_reference = claim.external_ref or claim.numero_sinistro or claim.id
        claim_context = CommunicationClaimContext(
            claim_id=claim.id,
            claim_reference=claim_reference,
            claim_number=claim.numero_sinistro or claim.external_ref,
            claim_status=claim.stato_corrente,
            insured_name=claim.nome_assicurato,
        )
        return CommunicationCallerContext(
            display_name=match.display_name or claim.nome_assicurato or claim_reference or raw_phone,
            source="claim",
            contact_type=match.role,
            phone_number=raw_phone,
            claim_context=claim_context,
        )

    async def _rubrica_context_for_phone(
        self,
        db: AsyncSession,
        tenant_id: str,
        compact: str,
        raw_phone: str,
    ) -> CommunicationCallerContext | None:
        pattern = self._phone_pattern(compact)

        agent_result = await db.execute(
            select(RubricaAgente).where(
                RubricaAgente.tenant_id == tenant_id,
                RubricaAgente.is_active == True,
                RubricaAgente.telefono.ilike(pattern),
            ).limit(1)
        )
        agent = agent_result.scalar_one_or_none()
        if agent:
            return CommunicationCallerContext(
                display_name=self._person_name(agent.nome, agent.cognome) or raw_phone,
                source="rubrica",
                contact_type="agent",
                phone_number=raw_phone,
            )

        agency_result = await db.execute(
            select(RubricaAgenzia).where(
                RubricaAgenzia.tenant_id == tenant_id,
                RubricaAgenzia.is_active == True,
                RubricaAgenzia.telefono.ilike(pattern),
            ).limit(1)
        )
        agency = agency_result.scalar_one_or_none()
        if agency:
            return CommunicationCallerContext(
                display_name=agency.nome or raw_phone,
                source="rubrica",
                contact_type="agency",
                phone_number=raw_phone,
            )

        liquidator_result = await db.execute(
            select(RubricaLiquidatore).where(
                RubricaLiquidatore.tenant_id == tenant_id,
                RubricaLiquidatore.is_active == True,
                RubricaLiquidatore.telefono.ilike(pattern),
            ).limit(1)
        )
        liquidator = liquidator_result.scalar_one_or_none()
        if liquidator:
            return CommunicationCallerContext(
                display_name=self._person_name(liquidator.nome, liquidator.cognome) or raw_phone,
                source="rubrica",
                contact_type="liquidator",
                phone_number=raw_phone,
            )

        return None

    def _matched_claim_phone(self, claim: Claim, compact: str) -> MatchedPhoneField:
        fields = [
            MatchedPhoneField("insured", claim.telefono_assicurato, claim.nome_assicurato),
            MatchedPhoneField("contractor", claim.telefono_contraente, claim.nome_contraente),
            MatchedPhoneField("damaged_party", claim.telefono_danneggiato, claim.nome_danneggiato),
            MatchedPhoneField("agency", claim.telefono_agenzia, claim.agenzia),
        ]
        for field in fields:
            if self._phone_matches(field.phone, compact):
                return field
        return fields[0]

    def _phone_matches(self, candidate: str | None, compact: str) -> bool:
        if not candidate:
            return False
        candidate_compact = self._compact_phone(candidate)
        suffix_len = min(8, len(compact), len(candidate_compact))
        if suffix_len == 0:
            return False
        return candidate_compact[-suffix_len:] == compact[-suffix_len:]

    def _phone_pattern(self, compact: str) -> str:
        return f"%{compact[-8:]}%" if len(compact) >= 8 else f"%{compact}%"

    def _compact_phone(self, phone: str) -> str:
        return "".join(ch for ch in phone if ch.isdigit() or ch == "+")

    def _person_name(self, first_name: str | None, last_name: str | None) -> str | None:
        name = " ".join(part for part in [first_name, last_name] if part).strip()
        return name or None
