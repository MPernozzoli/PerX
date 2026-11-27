"""Operazioni della Regia. L'approvazione di una revisione esiste solo qui."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.chiari_stima import hash_economico, liquidabile_di, workflow_reclaim
from app.domain.regia_invariants import (
    EXECUTION_PHASES,
    META_STATES,
    OPEN_JOB_STATUSES,
    beneficiario_e_contraente,
    iban_richiede_questione,
    liquidabile_consentito,
    same_economy,
)
from app.models.claim import Claim
from app.models.process_job import ProcessJob
from app.models.regia import (
    ClaimAtto,
    ClaimEstimateRevision,
    ClaimGroup,
    ClaimGroupMember,
    ClaimQuestion,
    ClaimWorkflow,
    TenantClaimState,
    TenantRule,
)
from app.models.tenant import Tenant
from app.models.user import User


def _now() -> datetime:
    return datetime.now(timezone.utc)


class RegiaError(ValueError):
    pass


class RegiaService:
    @staticmethod
    async def list_states(db: AsyncSession, tenant_id: str) -> list[TenantClaimState]:
        result = await db.execute(
            select(TenantClaimState)
            .where(TenantClaimState.tenant_id == tenant_id, TenantClaimState.active.is_(True))
            .order_by(TenantClaimState.sort_order.asc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def set_state(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str,
        code: str,
        source: str,
        job_id: str | None = None,
    ) -> Claim:
        claim = await _claim(db, tenant_id, claim_id)
        state = await _state(db, tenant_id, code)
        if state.is_meta or code in META_STATES:
            raise RegiaError("Questo stato si mostra solo mentre un lavoro è in corso")
        workflow = await _workflow(db, claim)
        if source != "perito":
            job = await _open_job(db, tenant_id, claim_id, job_id)
            if job is None:
                raise RegiaError("Un agente cambia stato solo dentro un lavoro aperto")
            if (
                workflow.manual_state_at
                and job.started_at
                and workflow.manual_state_at >= job.started_at
            ):
                raise RegiaError("Il perito ha scelto lo stato dopo l'inizio del lavoro")
        claim.stato_corrente = code
        if code == "CHIUSO" and claim.closed_at is None:
            claim.closed_at = _now()
        if source == "perito":
            workflow.manual_state_code = code
            workflow.manual_state_at = _now()
        await db.flush()
        return claim

    @staticmethod
    async def save_revision(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str,
        revision_number: int,
        input_json: dict,
        calculation_json: dict,
        amount_exception_reason: str | None = None,
    ) -> ClaimEstimateRevision:
        claim = await _claim(db, tenant_id, claim_id)
        existing = (
            await db.execute(
                select(ClaimEstimateRevision).where(
                    ClaimEstimateRevision.claim_id == claim.id,
                    ClaimEstimateRevision.revision_number == revision_number,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            raise RegiaError("Revisione già presente")
        previous = (
            await db.execute(
                select(ClaimEstimateRevision)
                .where(ClaimEstimateRevision.claim_id == claim.id)
                .order_by(ClaimEstimateRevision.revision_number.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        economic = hash_economico(calculation_json)
        liquidabile = liquidabile_di(calculation_json)
        if liquidabile is None:
            raise RegiaError("Il calcolo non ha un liquidabile")
        proposed = await _max_proposed_amount(db, claim.id)
        if not liquidabile_consentito(liquidabile, proposed, amount_exception_reason):
            raise RegiaError("Il liquidabile è inferiore a un importo già proposto")
        revision = ClaimEstimateRevision(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            revision_number=revision_number,
            input_json=input_json,
            calculation_json=calculation_json,
            calculation_hash=calculation_json.get("hash_calcolo"),
            economic_hash=economic,
            liquidabile=liquidabile,
            amount_exception_reason=(amount_exception_reason or "").strip() or None,
        )
        if previous and previous.approved_at and same_economy(previous.economic_hash, economic):
            revision.approved_at = previous.approved_at
            revision.approved_by_user_id = previous.approved_by_user_id
            revision.inherited_from_revision_id = previous.id
        if previous and previous.superseded_at is None:
            previous.superseded_at = _now()
        db.add(revision)
        selezione = (calculation_json.get("selezione_allegati") or {}) if isinstance(calculation_json, dict) else {}
        workflow = workflow_reclaim(
            liquidabile,
            esito=str(selezione.get("esito") or ""),
            reclaim_over=bool(selezione.get("reclaim_over")),
            reclaim_assente=bool(selezione.get("reclaim_assente")),
        )
        profile = await _workflow(db, claim)
        profile.reclaim_model = workflow["reclaim"]["modello"]
        await db.flush()
        return revision

    @staticmethod
    async def approve_revision(
        db: AsyncSession,
        *,
        tenant_id: str,
        revision_id: str,
        user: User,
    ) -> ClaimEstimateRevision:
        revision = await _revision(db, tenant_id, revision_id)
        if revision.approved_at is not None:
            return revision
        revision.approved_at = _now()
        revision.approved_by_user_id = user.id
        revision.inherited_from_revision_id = None
        await db.flush()
        return revision

    @staticmethod
    async def open_question(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str | None,
        job_id: str | None,
        question_type: str,
        description: str,
        raised_level: str | None = None,
        evidence: dict | list | None = None,
        options: list | None = None,
        recommendation: str | None = None,
    ) -> ClaimQuestion:
        if claim_id:
            await _claim(db, tenant_id, claim_id)
        question = ClaimQuestion(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            job_id=job_id,
            question_type=question_type,
            raised_level=raised_level,
            description=description.strip(),
            evidence_json=evidence,
            options_json=options,
            recommendation=recommendation,
            status="aperta",
        )
        db.add(question)
        await db.flush()
        return question

    @staticmethod
    async def answer_question(
        db: AsyncSession,
        *,
        tenant_id: str,
        question_id: str,
        user: User,
        answer_text: str,
        scope: str,
    ) -> tuple[ClaimQuestion, TenantRule | None]:
        if scope not in {"pratica", "sempre"}:
            raise RegiaError("La risposta vale per questa pratica o per sempre")
        question = (
            await db.execute(
                select(ClaimQuestion).where(
                    ClaimQuestion.id == question_id,
                    ClaimQuestion.tenant_id == tenant_id,
                )
            )
        ).scalar_one_or_none()
        if question is None:
            raise RegiaError("Questione non trovata")
        if question.status != "aperta":
            raise RegiaError("Questione già chiusa")
        question.answer_text = answer_text.strip()
        question.answer_scope = scope
        question.answered_by_user_id = user.id
        question.answered_at = _now()
        question.status = "risposta"
        rule = None
        if scope == "sempre":
            rule = TenantRule(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                body=answer_text.strip(),
                rule_type="istruzione",
                scope="tenant",
                author="perito",
                origin_claim_ref=None,
                status="proposta",
                version=1,
            )
            question.outcome = "regola_proposta"
            db.add(rule)
        else:
            question.outcome = "solo_pratica"
        await db.flush()
        return question, rule

    @staticmethod
    async def confirm_rule(db: AsyncSession, *, tenant_id: str, rule_id: str) -> TenantRule:
        rule = (
            await db.execute(select(TenantRule).where(TenantRule.id == rule_id, TenantRule.tenant_id == tenant_id))
        ).scalar_one_or_none()
        if rule is None:
            raise RegiaError("Regola non trovata")
        if rule.status == "attiva":
            return rule
        rule.status = "attiva"
        await db.flush()
        return rule

    @staticmethod
    async def register_signed_iban(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str,
        iban: str,
        beneficiary: str | None,
        amount: Decimal | None = None,
    ) -> tuple[ClaimAtto | None, ClaimQuestion | None]:
        claim = await _claim(db, tenant_id, claim_id)
        previous = (
            await db.execute(
                select(ClaimAtto)
                .where(ClaimAtto.claim_id == claim.id, ClaimAtto.iban.is_not(None))
                .order_by(ClaimAtto.created_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        holder = claim.nome_contraente or claim.nome_assicurato
        question_type = iban_richiede_questione(
            iban_precedente=previous.iban if previous else None,
            iban_nuovo=iban,
            beneficiario_e_intestatario=beneficiario_e_contraente(beneficiary, holder),
        )
        if question_type:
            question = await RegiaService.open_question(
                db,
                tenant_id=tenant_id,
                claim_id=claim.id,
                job_id=None,
                question_type=question_type,
                description="L'IBAN dell'atto firmato va verificato dal perito.",
                raised_level="L1",
                evidence={"iban": iban, "beneficiario": beneficiary},
                recommendation="Tieni l'IBAN solo se è dell'intestatario e il mod-97 torna.",
            )
            return None, question
        atto = ClaimAtto(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            kind="firmato",
            amount=amount,
            signed_at=_now(),
            iban="".join(iban.split()).upper(),
            iban_verified=True,
            beneficiary=beneficiary,
        )
        db.add(atto)
        await db.flush()
        return atto, None

    @staticmethod
    async def enqueue_job(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim_id: str,
        job_type: str,
        phase: str,
        resource: str,
        created_by_user_id: str | None,
        input_json: dict | None = None,
        model_level: str | None = None,
    ) -> ProcessJob:
        claim = await _claim(db, tenant_id, claim_id)
        open_job = (
            await db.execute(
                select(ProcessJob).where(
                    ProcessJob.tenant_id == tenant_id,
                    ProcessJob.claim_id == claim.id,
                    ProcessJob.phase.is_not(None),
                    ProcessJob.status.in_(tuple(OPEN_JOB_STATUSES)),
                )
            )
        ).scalar_one_or_none()
        if open_job is not None:
            raise RegiaError("C'è già un lavoro aperto su questa pratica")
        if phase in EXECUTION_PHASES:
            await _assert_group_approved(db, tenant_id, claim.id)
        job = ProcessJob(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            created_by_user_id=created_by_user_id,
            job_type=job_type,
            status="pending",
            input_json=input_json or {},
            phase=phase,
            resource=resource,
            model_level=model_level,
        )
        db.add(job)
        await db.flush()
        return job

    @staticmethod
    async def lease_next(
        db: AsyncSession,
        *,
        tenant_id: str,
        worker_id: str,
        resource: str | None = None,
    ) -> ProcessJob | None:
        if resource == "chrome":
            busy = (
                await db.execute(
                    select(ProcessJob.id).where(
                        ProcessJob.tenant_id == tenant_id,
                        ProcessJob.resource == "chrome",
                        ProcessJob.status == "processing",
                    )
                )
            ).first()
            if busy is not None:
                return None
        query = select(ProcessJob).where(
            ProcessJob.tenant_id == tenant_id,
            ProcessJob.status == "pending",
            ProcessJob.phase.is_not(None),
        )
        if resource:
            query = query.where(ProcessJob.resource == resource)
        job = (await db.execute(query.order_by(ProcessJob.created_at.asc()).limit(1))).scalar_one_or_none()
        if job is None:
            return None
        job.status = "processing"
        job.lease_owner = worker_id
        job.started_at = job.started_at or _now()
        job.last_heartbeat_at = _now()
        await db.flush()
        return job

    @staticmethod
    async def list_questions(db: AsyncSession, tenant_id: str, status: str | None = None) -> list[ClaimQuestion]:
        query = select(ClaimQuestion).where(ClaimQuestion.tenant_id == tenant_id)
        if status:
            query = query.where(ClaimQuestion.status == status)
        result = await db.execute(query.order_by(ClaimQuestion.created_at.desc()))
        return list(result.scalars().all())

    @staticmethod
    async def list_rules(db: AsyncSession, tenant_id: str) -> list[TenantRule]:
        result = await db.execute(
            select(TenantRule).where(TenantRule.tenant_id == tenant_id).order_by(TenantRule.created_at.desc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def list_jobs(db: AsyncSession, tenant_id: str) -> list[ProcessJob]:
        result = await db.execute(
            select(ProcessJob)
            .where(
                ProcessJob.tenant_id == tenant_id,
                ProcessJob.phase.is_not(None),
                ProcessJob.status.in_(tuple(OPEN_JOB_STATUSES)),
            )
            .order_by(ProcessJob.created_at.desc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def profile(db: AsyncSession, tenant: Tenant) -> dict:
        from app.domain.tenant_capabilities import capabilities_for, workflow_profile

        settings = tenant.settings_json or {}
        return {
            "tenant_id": tenant.id,
            "tenant_slug": tenant.slug,
            "workflow_profile": workflow_profile(settings),
            "single_operator": bool(settings.get("single_operator")),
            "capabilities": capabilities_for(settings),
        }


async def _claim(db: AsyncSession, tenant_id: str, claim_id: str) -> Claim:
    claim = await db.get(Claim, claim_id)
    if claim is None or claim.tenant_id != tenant_id:
        raise RegiaError("Pratica non trovata")
    return claim


async def _state(db: AsyncSession, tenant_id: str, code: str) -> TenantClaimState:
    state = (
        await db.execute(
            select(TenantClaimState).where(
                TenantClaimState.tenant_id == tenant_id,
                TenantClaimState.code == code,
                TenantClaimState.active.is_(True),
            )
        )
    ).scalar_one_or_none()
    if state is None:
        raise RegiaError("Stato non previsto per questo studio")
    return state


async def _workflow(db: AsyncSession, claim: Claim) -> ClaimWorkflow:
    workflow = await db.get(ClaimWorkflow, claim.id)
    if workflow is None:
        workflow = ClaimWorkflow(claim_id=claim.id, tenant_id=claim.tenant_id)
        db.add(workflow)
        await db.flush()
    return workflow


async def _revision(db: AsyncSession, tenant_id: str, revision_id: str) -> ClaimEstimateRevision:
    revision = await db.get(ClaimEstimateRevision, revision_id)
    if revision is None or revision.tenant_id != tenant_id:
        raise RegiaError("Revisione non trovata")
    return revision


async def _open_job(db: AsyncSession, tenant_id: str, claim_id: str, job_id: str | None) -> ProcessJob | None:
    if job_id:
        job = await db.get(ProcessJob, job_id)
        if job and job.tenant_id == tenant_id and job.claim_id == claim_id and job.status in OPEN_JOB_STATUSES:
            return job
        return None
    return (
        await db.execute(
            select(ProcessJob).where(
                ProcessJob.tenant_id == tenant_id,
                ProcessJob.claim_id == claim_id,
                ProcessJob.phase.is_not(None),
                ProcessJob.status.in_(tuple(OPEN_JOB_STATUSES)),
            )
        )
    ).scalar_one_or_none()


async def _max_proposed_amount(db: AsyncSession, claim_id: str) -> Decimal | None:
    result = await db.execute(
        select(func.max(ClaimAtto.amount)).where(ClaimAtto.claim_id == claim_id, ClaimAtto.kind == "inviato")
    )
    value = result.scalar_one_or_none()
    if value is None:
        return None
    return Decimal(str(value))


async def _assert_group_approved(db: AsyncSession, tenant_id: str, claim_id: str) -> None:
    memberships = (
        await db.execute(
            select(ClaimGroupMember.group_id)
            .join(ClaimGroup, ClaimGroup.id == ClaimGroupMember.group_id)
            .where(
                ClaimGroupMember.claim_id == claim_id,
                ClaimGroupMember.tenant_id == tenant_id,
                ClaimGroup.kind == "collegati",
            )
        )
    ).scalars().all()
    if not memberships:
        return
    member_ids = (
        await db.execute(select(ClaimGroupMember.claim_id).where(ClaimGroupMember.group_id.in_(memberships)))
    ).scalars().all()
    for member_id in member_ids:
        latest = (
            await db.execute(
                select(ClaimEstimateRevision)
                .where(ClaimEstimateRevision.claim_id == member_id)
                .order_by(ClaimEstimateRevision.revision_number.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if latest is None or latest.approved_at is None:
            raise RegiaError("I sinistri collegati si eseguono solo quando tutte le stime sono approvate")
