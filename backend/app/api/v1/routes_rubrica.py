"""
Rubrica routes: agenzie, agenti e liquidatori (tenant-scoped address book)
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.rubrica import RubricaAgente, RubricaAgenzia, RubricaLiquidatore
from app.models.user import User
from app.schemas.rubrica import (
    AgenziaCreate,
    AgenziaListResponse,
    AgenziaResponse,
    AgenziaUpdate,
    AgenteCreate,
    AgenteListResponse,
    AgenteResponse,
    AgenteUpdate,
    LiquidatoreCreate,
    LiquidatoreListResponse,
    LiquidatoreResponse,
    LiquidatoreUpdate,
    RubricaAllResponse,
)

router = APIRouter()


# ======================================================================
# AGENZIE
# ======================================================================

@router.get("/agenzie", response_model=AgenziaListResponse)
async def list_agenzie(
    search: str | None = Query(None),
    compagnia: str | None = Query(None),
    is_active: bool | None = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(RubricaAgenzia).where(RubricaAgenzia.tenant_id == current_user.tenant_id)

    if search:
        like = f"%{search}%"
        query = query.where(
            or_(
                RubricaAgenzia.nome.ilike(like),
                RubricaAgenzia.codice.ilike(like),
                RubricaAgenzia.citta.ilike(like),
                RubricaAgenzia.email.ilike(like),
            )
        )
    if compagnia is not None:
        query = query.where(RubricaAgenzia.compagnia == compagnia)
    if is_active is not None:
        query = query.where(RubricaAgenzia.is_active == is_active)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(RubricaAgenzia.nome.asc()).offset(skip).limit(limit))
    items = result.scalars().all()
    return AgenziaListResponse(items=[AgenziaResponse.model_validate(i) for i in items], total=total)


@router.post("/agenzie", response_model=AgenziaResponse, status_code=status.HTTP_201_CREATED)
async def create_agenzia(
    payload: AgenziaCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    data = payload.model_dump()
    agenzia_id = data.pop("id", None) or str(uuid.uuid4())
    agenzia = RubricaAgenzia(
        id=agenzia_id,
        tenant_id=current_user.tenant_id,
        **data,
    )
    db.add(agenzia)
    await db.commit()
    await db.refresh(agenzia)
    return AgenziaResponse.model_validate(agenzia)


@router.get("/agenzie/{agenzia_id}", response_model=AgenziaResponse)
async def get_agenzia(
    agenzia_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(RubricaAgenzia).where(
            RubricaAgenzia.id == agenzia_id,
            RubricaAgenzia.tenant_id == current_user.tenant_id,
        )
    )
    agenzia = result.scalar_one_or_none()
    if not agenzia:
        raise HTTPException(status_code=404, detail="Agenzia not found")
    return AgenziaResponse.model_validate(agenzia)


@router.put("/agenzie/{agenzia_id}", response_model=AgenziaResponse)
async def update_agenzia(
    agenzia_id: str,
    payload: AgenziaUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(RubricaAgenzia).where(
            RubricaAgenzia.id == agenzia_id,
            RubricaAgenzia.tenant_id == current_user.tenant_id,
        )
    )
    agenzia = result.scalar_one_or_none()
    if not agenzia:
        raise HTTPException(status_code=404, detail="Agenzia not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(agenzia, field, value)
    agenzia.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(agenzia)
    return AgenziaResponse.model_validate(agenzia)


@router.delete("/agenzie/{agenzia_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_agenzia(
    agenzia_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Soft delete: sets is_active=False."""
    result = await db.execute(
        select(RubricaAgenzia).where(
            RubricaAgenzia.id == agenzia_id,
            RubricaAgenzia.tenant_id == current_user.tenant_id,
        )
    )
    agenzia = result.scalar_one_or_none()
    if not agenzia:
        raise HTTPException(status_code=404, detail="Agenzia not found")
    agenzia.is_active = False
    agenzia.updated_at = datetime.now(timezone.utc)

    agents = await db.execute(
        select(RubricaAgente).where(
            RubricaAgente.tenant_id == current_user.tenant_id,
            RubricaAgente.agenzia_id == agenzia_id,
        )
    )
    for agente in agents.scalars().all():
        agente.is_active = False
        agente.updated_at = datetime.now(timezone.utc)

    await db.commit()


# ======================================================================
# AGENTI
# ======================================================================

@router.get("/agenti", response_model=AgenteListResponse)
async def list_agenti(
    search: str | None = Query(None),
    agenzia_id: str | None = Query(None),
    is_active: bool | None = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(RubricaAgente).where(RubricaAgente.tenant_id == current_user.tenant_id)

    if search:
        like = f"%{search}%"
        query = query.where(
            or_(
                RubricaAgente.cognome.ilike(like),
                RubricaAgente.nome.ilike(like),
                RubricaAgente.email.ilike(like),
                RubricaAgente.ruolo.ilike(like),
            )
        )
    if agenzia_id is not None:
        query = query.where(RubricaAgente.agenzia_id == agenzia_id)
    if is_active is not None:
        query = query.where(RubricaAgente.is_active == is_active)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(RubricaAgente.cognome.asc(), RubricaAgente.nome.asc()).offset(skip).limit(limit))
    items = result.scalars().all()
    return AgenteListResponse(items=[AgenteResponse.model_validate(i) for i in items], total=total)


@router.post("/agenti", response_model=AgenteResponse, status_code=status.HTTP_201_CREATED)
async def create_agente(
    payload: AgenteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _ensure_agenzia_exists(payload.agenzia_id, db, current_user)
    data = payload.model_dump()
    agente_id = data.pop("id", None) or str(uuid.uuid4())
    agente = RubricaAgente(
        id=agente_id,
        tenant_id=current_user.tenant_id,
        **data,
    )
    db.add(agente)
    await db.commit()
    await db.refresh(agente)
    return AgenteResponse.model_validate(agente)


@router.get("/agenti/{agente_id}", response_model=AgenteResponse)
async def get_agente(
    agente_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    agente = await _get_agente_or_404(agente_id, db, current_user)
    return AgenteResponse.model_validate(agente)


@router.put("/agenti/{agente_id}", response_model=AgenteResponse)
async def update_agente(
    agente_id: str,
    payload: AgenteUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    agente = await _get_agente_or_404(agente_id, db, current_user)

    data = payload.model_dump(exclude_unset=True)
    if "agenzia_id" in data and data["agenzia_id"] is not None:
        await _ensure_agenzia_exists(data["agenzia_id"], db, current_user)
    for field, value in data.items():
        setattr(agente, field, value)
    agente.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(agente)
    return AgenteResponse.model_validate(agente)


@router.delete("/agenti/{agente_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_agente(
    agente_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    agente = await _get_agente_or_404(agente_id, db, current_user)
    agente.is_active = False
    agente.updated_at = datetime.now(timezone.utc)
    await db.commit()


# ======================================================================
# LIQUIDATORI
# ======================================================================

@router.get("/liquidatori", response_model=LiquidatoreListResponse)
async def list_liquidatori(
    search: str | None = Query(None),
    compagnia: str | None = Query(None),
    is_active: bool | None = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(RubricaLiquidatore).where(RubricaLiquidatore.tenant_id == current_user.tenant_id)

    if search:
        like = f"%{search}%"
        query = query.where(
            or_(
                RubricaLiquidatore.cognome.ilike(like),
                RubricaLiquidatore.nome.ilike(like),
                RubricaLiquidatore.email.ilike(like),
            )
        )
    if compagnia is not None:
        query = query.where(RubricaLiquidatore.compagnia == compagnia)
    if is_active is not None:
        query = query.where(RubricaLiquidatore.is_active == is_active)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(RubricaLiquidatore.cognome.asc()).offset(skip).limit(limit))
    items = result.scalars().all()
    return LiquidatoreListResponse(items=[LiquidatoreResponse.model_validate(i) for i in items], total=total)


@router.post("/liquidatori", response_model=LiquidatoreResponse, status_code=status.HTTP_201_CREATED)
async def create_liquidatore(
    payload: LiquidatoreCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    data = payload.model_dump()
    liquidatore_id = data.pop("id", None) or str(uuid.uuid4())
    liquidatore = RubricaLiquidatore(
        id=liquidatore_id,
        tenant_id=current_user.tenant_id,
        **data,
    )
    db.add(liquidatore)
    await db.commit()
    await db.refresh(liquidatore)
    return LiquidatoreResponse.model_validate(liquidatore)


@router.put("/liquidatori/{liquidatore_id}", response_model=LiquidatoreResponse)
async def update_liquidatore(
    liquidatore_id: str,
    payload: LiquidatoreUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(RubricaLiquidatore).where(
            RubricaLiquidatore.id == liquidatore_id,
            RubricaLiquidatore.tenant_id == current_user.tenant_id,
        )
    )
    liquidatore = result.scalar_one_or_none()
    if not liquidatore:
        raise HTTPException(status_code=404, detail="Liquidatore not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(liquidatore, field, value)
    liquidatore.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(liquidatore)
    return LiquidatoreResponse.model_validate(liquidatore)


@router.delete("/liquidatori/{liquidatore_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_liquidatore(
    liquidatore_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Soft delete: sets is_active=False."""
    result = await db.execute(
        select(RubricaLiquidatore).where(
            RubricaLiquidatore.id == liquidatore_id,
            RubricaLiquidatore.tenant_id == current_user.tenant_id,
        )
    )
    liquidatore = result.scalar_one_or_none()
    if not liquidatore:
        raise HTTPException(status_code=404, detail="Liquidatore not found")
    liquidatore.is_active = False
    liquidatore.updated_at = datetime.now(timezone.utc)
    await db.commit()


# ======================================================================
# COMBINED SYNC
# ======================================================================

@router.get("/all", response_model=RubricaAllResponse)
async def get_all_rubrica(
    updated_since: datetime | None = Query(None, description="ISO8601 — returns only records updated after this timestamp"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Differential sync endpoint. Returns active agenzie + agenti + liquidatori together."""
    agenzie_q = select(RubricaAgenzia).where(
        RubricaAgenzia.tenant_id == current_user.tenant_id,
        RubricaAgenzia.is_active == True,  # noqa: E712
    )
    agenti_q = select(RubricaAgente).where(
        RubricaAgente.tenant_id == current_user.tenant_id,
        RubricaAgente.is_active == True,  # noqa: E712
    )
    liq_q = select(RubricaLiquidatore).where(
        RubricaLiquidatore.tenant_id == current_user.tenant_id,
        RubricaLiquidatore.is_active == True,  # noqa: E712
    )

    if updated_since:
        agenzie_q = agenzie_q.where(RubricaAgenzia.updated_at > updated_since)
        agenti_q = agenti_q.where(RubricaAgente.updated_at > updated_since)
        liq_q = liq_q.where(RubricaLiquidatore.updated_at > updated_since)

    agenzie = (await db.execute(agenzie_q.order_by(RubricaAgenzia.updated_at.asc()))).scalars().all()
    agenti = (await db.execute(agenti_q.order_by(RubricaAgente.updated_at.asc()))).scalars().all()
    liquidatori = (await db.execute(liq_q.order_by(RubricaLiquidatore.updated_at.asc()))).scalars().all()

    return RubricaAllResponse(
        agenzie=[AgenziaResponse.model_validate(a) for a in agenzie],
        agenti=[AgenteResponse.model_validate(a) for a in agenti],
        liquidatori=[LiquidatoreResponse.model_validate(l) for l in liquidatori],
        synced_at=datetime.now(timezone.utc),
    )


async def _ensure_agenzia_exists(
    agenzia_id: str,
    db: AsyncSession,
    current_user: User,
) -> None:
    result = await db.execute(
        select(RubricaAgenzia.id).where(
            RubricaAgenzia.id == agenzia_id,
            RubricaAgenzia.tenant_id == current_user.tenant_id,
            RubricaAgenzia.is_active == True,  # noqa: E712
        )
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Agenzia not found")


async def _get_agente_or_404(
    agente_id: str,
    db: AsyncSession,
    current_user: User,
) -> RubricaAgente:
    result = await db.execute(
        select(RubricaAgente).where(
            RubricaAgente.id == agente_id,
            RubricaAgente.tenant_id == current_user.tenant_id,
        )
    )
    agente = result.scalar_one_or_none()
    if not agente:
        raise HTTPException(status_code=404, detail="Agente not found")
    return agente
