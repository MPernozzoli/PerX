"""
Rubrica routes: agenzie e liquidatori (tenant-scoped address book)
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.rubrica import RubricaAgenzia, RubricaLiquidatore
from app.models.user import User
from app.schemas.rubrica import (
    AgenziaCreate,
    AgenziaListResponse,
    AgenziaResponse,
    AgenziaUpdate,
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
    agenzia = RubricaAgenzia(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        **payload.model_dump(),
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
    liquidatore = RubricaLiquidatore(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        **payload.model_dump(),
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
    """Differential sync endpoint. Returns agenzie + liquidatori together."""
    agenzie_q = select(RubricaAgenzia).where(RubricaAgenzia.tenant_id == current_user.tenant_id)
    liq_q = select(RubricaLiquidatore).where(RubricaLiquidatore.tenant_id == current_user.tenant_id)

    if updated_since:
        agenzie_q = agenzie_q.where(RubricaAgenzia.updated_at > updated_since)
        liq_q = liq_q.where(RubricaLiquidatore.updated_at > updated_since)

    agenzie = (await db.execute(agenzie_q.order_by(RubricaAgenzia.updated_at.asc()))).scalars().all()
    liquidatori = (await db.execute(liq_q.order_by(RubricaLiquidatore.updated_at.asc()))).scalars().all()

    return RubricaAllResponse(
        agenzie=[AgenziaResponse.model_validate(a) for a in agenzie],
        liquidatori=[LiquidatoreResponse.model_validate(l) for l in liquidatori],
        synced_at=datetime.now(timezone.utc),
    )
