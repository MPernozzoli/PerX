"""Sala regia: profilo, stati, revisioni, questioni, regole, job."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.regia import (
    JobCreateRequest,
    JobResponse,
    QuestionAnswerRequest,
    QuestionCreateRequest,
    QuestionResponse,
    RegiaProfileResponse,
    RevisionCreateRequest,
    RevisionResponse,
    RuleResponse,
    SignedIbanRequest,
    StateChangeRequest,
    TenantStateResponse,
)
from app.services.regia_service import RegiaError, RegiaService

router = APIRouter()


async def _tenant(db: AsyncSession, user: User) -> Tenant:
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Studio non trovato")
    return tenant


def _as_http(exc: RegiaError) -> HTTPException:
    detail = str(exc)
    code = status.HTTP_404_NOT_FOUND if "non trovat" in detail else status.HTTP_409_CONFLICT
    return HTTPException(status_code=code, detail=detail)


@router.get("/profilo", response_model=RegiaProfileResponse)
async def regia_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    tenant = await _tenant(db, current_user)
    return await RegiaService.profile(db, tenant)


@router.get("/stati", response_model=list[TenantStateResponse])
async def list_states(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    rows = await RegiaService.list_states(db, current_user.tenant_id)
    return [
        TenantStateResponse(
            code=row.code,
            label=row.label,
            description=row.description,
            actor=row.actor,
            is_meta=row.is_meta,
            sort_order=row.sort_order,
        )
        for row in rows
    ]


@router.post("/pratiche/{claim_id}/stato")
async def change_state(
    claim_id: str,
    payload: StateChangeRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    source = "perito"
    try:
        claim = await RegiaService.set_state(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=claim_id,
            code=payload.code,
            source=source,
            job_id=payload.job_id,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return {"claim_id": claim.id, "stato": claim.stato_corrente}


@router.post("/pratiche/{claim_id}/revisioni", response_model=RevisionResponse, status_code=status.HTTP_201_CREATED)
async def save_revision(
    claim_id: str,
    payload: RevisionCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        revision = await RegiaService.save_revision(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=claim_id,
            revision_number=payload.revision_number,
            input_json=payload.input_json,
            calculation_json=payload.calculation_json,
            amount_exception_reason=payload.amount_exception_reason,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return revision


@router.post("/revisioni/{revision_id}/approva", response_model=RevisionResponse)
async def approve_revision(
    revision_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        revision = await RegiaService.approve_revision(
            db,
            tenant_id=current_user.tenant_id,
            revision_id=revision_id,
            user=current_user,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return revision


@router.get("/questioni", response_model=list[QuestionResponse])
async def list_questions(
    stato: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    return await RegiaService.list_questions(db, current_user.tenant_id, stato)


@router.post("/questioni", response_model=QuestionResponse, status_code=status.HTTP_201_CREATED)
async def open_question(
    payload: QuestionCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        question = await RegiaService.open_question(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=payload.claim_id,
            job_id=payload.job_id,
            question_type=payload.question_type,
            description=payload.description,
            raised_level=payload.raised_level,
            evidence=payload.evidence,
            options=payload.options,
            recommendation=payload.recommendation,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return question


@router.post("/questioni/{question_id}/risposta", response_model=QuestionResponse)
async def answer_question(
    question_id: str,
    payload: QuestionAnswerRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        question, _rule = await RegiaService.answer_question(
            db,
            tenant_id=current_user.tenant_id,
            question_id=question_id,
            user=current_user,
            answer_text=payload.answer_text,
            scope=payload.scope,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return question


@router.get("/regole", response_model=list[RuleResponse])
async def list_rules(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    return await RegiaService.list_rules(db, current_user.tenant_id)


@router.post("/regole/{rule_id}/conferma", response_model=RuleResponse)
async def confirm_rule(
    rule_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        rule = await RegiaService.confirm_rule(db, tenant_id=current_user.tenant_id, rule_id=rule_id)
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return rule


@router.get("/lavori", response_model=list[JobResponse])
async def list_jobs(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    return await RegiaService.list_jobs(db, current_user.tenant_id)


@router.post("/lavori", response_model=JobResponse, status_code=status.HTTP_201_CREATED)
async def enqueue_job(
    payload: JobCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        job = await RegiaService.enqueue_job(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=payload.claim_id,
            job_type=payload.job_type,
            phase=payload.phase,
            resource=payload.resource,
            created_by_user_id=current_user.id,
            input_json=payload.input_json,
            model_level=payload.model_level,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return job


@router.post("/pratiche/{claim_id}/atto-firmato/iban")
async def register_signed_iban(
    claim_id: str,
    payload: SignedIbanRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        atto, question = await RegiaService.register_signed_iban(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=claim_id,
            iban=payload.iban,
            beneficiary=payload.beneficiary,
            amount=payload.amount,
        )
        await db.commit()
    except RegiaError as exc:
        raise _as_http(exc) from exc
    return {
        "registrato": atto is not None,
        "atto_id": atto.id if atto else None,
        "questione_id": question.id if question else None,
        "questione_tipo": question.question_type if question else None,
    }
