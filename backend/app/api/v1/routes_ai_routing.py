"""
Endpoint runtime per client AI (iOS, PerXHub, futuri agent).

Differente da `routes_ai_prompts.py` che è admin-only per editing: questo
router serve i client che eseguono effettivamente le analisi.

- GET    /api/v1/ai-routing/policy
        Tutte le righe policy visibili dal tenant (override + default globale).
        Il client le carica all'avvio e le cacha; il routing viene poi deciso
        localmente senza round-trip a ogni fase.

- GET    /api/v1/ai-routing/policy/{phase}/{trigger}
        Mode effettivo per (phase, trigger) per il tenant corrente.
        Fallback: tenant -> globale -> 'prefer_local'.

- PUT    /api/v1/ai-routing/policy/{phase}/{trigger}
        Imposta il mode (admin only). Crea o aggiorna l'override del tenant.

- POST   /api/v1/ai-routing/runs
        Log di un'esecuzione AI. Il client invia metadata (prompt_version_id,
        provider_used, model, latency_ms, status, trigger) per audit e
        osservabilità delle fasi.
"""
from __future__ import annotations

import uuid
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user, get_current_platform_admin
from app.models.ai_analysis_run import AIAnalysisRun, RUN_STATUSES
from app.models.ai_routing_policy import AIRoutingPolicy, ROUTING_MODES, ROUTING_TRIGGERS
from app.models.user import User
from app.services.ai_prompt_service import AIPromptService


router = APIRouter()


# --------------------------------------------------------------------------- #
# Prompts (lettura riservata agli amministratori Pynkstudio)
# --------------------------------------------------------------------------- #

class PromptBodyOut(BaseModel):
    key: str
    body: str
    variables: Optional[list[str]] = None
    version_id: Optional[str] = None


@router.get("/prompts/{key}", response_model=PromptBodyOut)
async def get_prompt_body(
    key: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    try:
        template = await AIPromptService.get_template(db, current_user.tenant_id, key)
    except LookupError:
        raise HTTPException(status_code=404, detail=f"Prompt {key!r} not found")
    return PromptBodyOut(
        key=template.key,
        body=template.body,
        variables=template.variables_json,
        version_id=template.current_version_id,
    )


@router.get("/prompts/{key}/versions/{version_id}", response_model=PromptBodyOut)
async def get_prompt_body_version(
    key: str,
    version_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    try:
        template = await AIPromptService.get_template(db, current_user.tenant_id, key)
        version = await AIPromptService.get_version(db, template.id, version_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return PromptBodyOut(
        key=template.key,
        body=version.body,
        variables=version.variables_json,
        version_id=version.version_id,
    )


# --------------------------------------------------------------------------- #
# Render prompt (server-side rendering per i client runtime)
# --------------------------------------------------------------------------- #
#
# I prompt body sono asset proprietari: gli endpoint GET sono platform_admin.
# I client (iOS, PerXHub) chiamano questo endpoint passando solo (phase,
# variabili di contesto) e ricevono testo gia renderizzato. Cosi:
#  - il body del template non lascia mai il backend in chiaro
#  - il client puo eseguire la chiamata AI (locale MLX o cloud) senza vedere
#    la "ricetta", solo il prompt finale contestualizzato
#  - per audit/riprocessing il client puo passare version_id per renderizzare
#    una versione storica esatta del prompt
#
# Il rendering attuale e str.format_map con _SafeDict (vedi AIPromptService).
# Variabili mancanti diventano stringa vuota: scelta voluta per non fallire
# su contesti incompleti (es. context_section opzionale del tagging).

class RenderPromptIn(BaseModel):
    phase: str = Field(..., description="Chiave del template, es. 'sinistri.tagging'")
    variables: dict[str, Any] = Field(default_factory=dict)
    version_id: Optional[str] = Field(
        None,
        description="Se passata, renderizza la versione storica indicata "
        "invece del current. Usato per riprocessing.",
    )


class RenderPromptOut(BaseModel):
    phase: str
    body_rendered: str
    version_id: Optional[str]


@router.post("/render-prompt", response_model=RenderPromptOut)
async def render_prompt(
    data: RenderPromptIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        template = await AIPromptService.get_template(
            db, current_user.tenant_id, data.phase
        )
    except LookupError:
        raise HTTPException(status_code=404, detail=f"Prompt {data.phase!r} not found")

    # Versione effettivamente usata (per logging client → ai_analysis_runs)
    effective_version_id = data.version_id or template.current_version_id

    try:
        rendered = await AIPromptService.render(
            db,
            current_user.tenant_id,
            data.phase,
            version_id=data.version_id,
            **{k: str(v) if v is not None else "" for k, v in data.variables.items()},
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    return RenderPromptOut(
        phase=data.phase,
        body_rendered=rendered,
        version_id=effective_version_id,
    )


# --------------------------------------------------------------------------- #
# Routing policy
# --------------------------------------------------------------------------- #

class RoutingPolicyOut(BaseModel):
    tenant_id: Optional[str]
    phase: str
    trigger: str
    mode: str


class RoutingPolicyIn(BaseModel):
    mode: str = Field(..., description="Uno tra: " + ", ".join(ROUTING_MODES))


class ResolvedRoutingOut(BaseModel):
    phase: str
    trigger: str
    mode: str


@router.get("/policy", response_model=list[RoutingPolicyOut])
async def list_policy(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Tutte le policy visibili dal tenant (override + default globale)."""
    rows = (
        await db.execute(
            select(AIRoutingPolicy).where(
                or_(
                    AIRoutingPolicy.tenant_id == current_user.tenant_id,
                    AIRoutingPolicy.tenant_id.is_(None),
                )
            )
        )
    ).scalars().all()
    return [
        RoutingPolicyOut(
            tenant_id=r.tenant_id, phase=r.phase, trigger=r.trigger, mode=r.mode
        )
        for r in rows
    ]


@router.get("/policy/{phase}/{trigger}", response_model=ResolvedRoutingOut)
async def resolve_policy(
    phase: str,
    trigger: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Mode effettivo per (phase, trigger). Fallback a 'prefer_local'."""
    if trigger not in ROUTING_TRIGGERS:
        raise HTTPException(status_code=400, detail=f"Invalid trigger {trigger!r}")
    mode = await AIPromptService.get_routing_mode(
        db, current_user.tenant_id, phase, trigger
    )
    return ResolvedRoutingOut(phase=phase, trigger=trigger, mode=mode)


@router.put("/policy/{phase}/{trigger}", response_model=RoutingPolicyOut)
async def upsert_policy(
    phase: str,
    trigger: str,
    data: RoutingPolicyIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    """Crea/aggiorna l'override tenant per (phase, trigger). Admin only."""
    if trigger not in ROUTING_TRIGGERS:
        raise HTTPException(status_code=400, detail=f"Invalid trigger {trigger!r}")
    if data.mode not in ROUTING_MODES:
        raise HTTPException(status_code=400, detail=f"Invalid mode {data.mode!r}")

    existing = (
        await db.execute(
            select(AIRoutingPolicy).where(
                AIRoutingPolicy.tenant_id == current_user.tenant_id,
                AIRoutingPolicy.phase == phase,
                AIRoutingPolicy.trigger == trigger,
            )
        )
    ).scalar_one_or_none()

    if existing is None:
        existing = AIRoutingPolicy(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            phase=phase,
            trigger=trigger,
            mode=data.mode,
            updated_by_user_id=current_user.id,
        )
        db.add(existing)
    else:
        existing.mode = data.mode
        existing.updated_by_user_id = current_user.id

    await db.commit()
    await db.refresh(existing)
    return RoutingPolicyOut(
        tenant_id=existing.tenant_id,
        phase=existing.phase,
        trigger=existing.trigger,
        mode=existing.mode,
    )


# --------------------------------------------------------------------------- #
# Analysis runs (log da client)
# --------------------------------------------------------------------------- #

class AnalysisRunIn(BaseModel):
    sinistro_ref: Optional[str] = None
    phase: str
    prompt_key: str
    prompt_version_id: str
    provider_used: str
    model_name: Optional[str] = None
    mode_applied: str
    trigger: str
    latency_ms: Optional[int] = None
    input_token_count: Optional[int] = None
    output_token_count: Optional[int] = None
    status: str
    error_message: Optional[str] = None
    client_id: Optional[str] = None


class AnalysisRunOut(BaseModel):
    id: str


@router.post("/runs", response_model=AnalysisRunOut)
async def log_analysis_run(
    data: AnalysisRunIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if data.status not in RUN_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status {data.status!r}")
    if data.trigger not in ROUTING_TRIGGERS:
        raise HTTPException(status_code=400, detail=f"Invalid trigger {data.trigger!r}")
    if data.mode_applied not in ROUTING_MODES:
        raise HTTPException(
            status_code=400, detail=f"Invalid mode_applied {data.mode_applied!r}"
        )

    run = AIAnalysisRun(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        sinistro_ref=data.sinistro_ref,
        phase=data.phase,
        prompt_key=data.prompt_key,
        prompt_version_id=data.prompt_version_id,
        provider_used=data.provider_used,
        model_name=data.model_name,
        mode_applied=data.mode_applied,
        trigger=data.trigger,
        latency_ms=data.latency_ms,
        input_token_count=data.input_token_count,
        output_token_count=data.output_token_count,
        status=data.status,
        error_message=data.error_message,
        client_id=data.client_id,
    )
    db.add(run)
    await db.commit()
    return AnalysisRunOut(id=run.id)
