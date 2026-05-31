"""
Routes per l'anagrafica unificata degli attori (contraente/assicurato/
danneggiato), i loro indirizzi/IBAN, le relazioni tra attori e le viste
cross-sinistro (claims, agenzie, compagnie).
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.actor import (
    ActorAddressCreate,
    ActorAddressResponse,
    ActorAddressUpdate,
    ActorAgencyLinkResponse,
    ActorCompanyLinkResponse,
    ActorCreate,
    ActorDetailResponse,
    ActorIbanCreate,
    ActorIbanResponse,
    ActorIbanUpdate,
    ActorListResponse,
    ActorRelationCreate,
    ActorRelationResponse,
    ActorResponse,
    ActorUpdate,
)
from app.schemas.claim import ClaimResponse
from app.services.actor_service import ActorService

router = APIRouter()


async def _load_or_404(db: AsyncSession, tenant_id: str, actor_id: str):
    actor = await ActorService.get_actor(db, tenant_id, actor_id)
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    return actor


# ----------------------------------------------------------------------
# Search / CRUD
# ----------------------------------------------------------------------

@router.get("", response_model=ActorListResponse)
async def list_actors(
    q: Optional[str] = Query(None, description="full-text su nome/cognome/denominazione/CF/PIVA/email"),
    actor_type: Optional[str] = Query(None, description="person|company|condo"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    items, total = await ActorService.search(
        db, current_user.tenant_id, query=q, actor_type=actor_type, limit=limit, offset=offset,
    )
    return ActorListResponse(items=[ActorResponse.model_validate(a) for a in items], total=total)


@router.post("", response_model=ActorResponse, status_code=status.HTTP_201_CREATED)
async def create_actor(
    payload: ActorCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    actor, _ = await ActorService.upsert_by_cf_or_piva(db, current_user.tenant_id, payload)
    return ActorResponse.model_validate(actor)


@router.get("/{actor_id}", response_model=ActorDetailResponse)
async def get_actor(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    actor = await _load_or_404(db, current_user.tenant_id, actor_id)
    addrs = await ActorService.list_addresses(db, actor_id)
    ibans = await ActorService.list_ibans(db, actor_id)
    rel_out, rel_in = await ActorService.list_relations(db, actor_id)
    return ActorDetailResponse(
        **ActorResponse.model_validate(actor).model_dump(),
        addresses=[ActorAddressResponse.model_validate(a) for a in addrs],
        ibans=[ActorIbanResponse.model_validate(i) for i in ibans],
        relations_out=[ActorRelationResponse.model_validate(r) for r in rel_out],
        relations_in=[ActorRelationResponse.model_validate(r) for r in rel_in],
    )


@router.patch("/{actor_id}", response_model=ActorResponse)
async def update_actor(
    actor_id: str,
    payload: ActorUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    actor = await ActorService.update_actor(db, current_user.tenant_id, actor_id, payload)
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    return ActorResponse.model_validate(actor)


# ----------------------------------------------------------------------
# Addresses
# ----------------------------------------------------------------------

@router.get("/{actor_id}/addresses", response_model=list[ActorAddressResponse])
async def list_addresses(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    items = await ActorService.list_addresses(db, actor_id)
    return [ActorAddressResponse.model_validate(a) for a in items]


@router.post("/{actor_id}/addresses", response_model=ActorAddressResponse, status_code=status.HTTP_201_CREATED)
async def add_address(
    actor_id: str,
    payload: ActorAddressCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    addr = await ActorService.add_address(db, actor_id, payload)
    return ActorAddressResponse.model_validate(addr)


# ----------------------------------------------------------------------
# IBAN
# ----------------------------------------------------------------------

@router.get("/{actor_id}/ibans", response_model=list[ActorIbanResponse])
async def list_ibans(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    items = await ActorService.list_ibans(db, actor_id)
    return [ActorIbanResponse.model_validate(i) for i in items]


@router.post("/{actor_id}/ibans", response_model=ActorIbanResponse, status_code=status.HTTP_201_CREATED)
async def add_iban(
    actor_id: str,
    payload: ActorIbanCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    iban = await ActorService.add_iban(db, actor_id, payload)
    return ActorIbanResponse.model_validate(iban)


# ----------------------------------------------------------------------
# Relations
# ----------------------------------------------------------------------

@router.post("/{actor_id}/relations", response_model=ActorRelationResponse, status_code=status.HTTP_201_CREATED)
async def add_relation(
    actor_id: str,
    payload: ActorRelationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if payload.from_actor_id != actor_id:
        raise HTTPException(status_code=400, detail="from_actor_id_mismatch")
    await _load_or_404(db, current_user.tenant_id, actor_id)
    await _load_or_404(db, current_user.tenant_id, payload.to_actor_id)
    rel = await ActorService.add_relation(
        db,
        from_actor_id=payload.from_actor_id,
        to_actor_id=payload.to_actor_id,
        relation_type=payload.relation_type,
        note=payload.note,
    )
    return ActorRelationResponse.model_validate(rel)


# ----------------------------------------------------------------------
# Cross-claim views
# ----------------------------------------------------------------------

@router.get("/{actor_id}/claims", response_model=list[ClaimResponse])
async def list_actor_claims(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    claims = await ActorService.list_claims(db, current_user.tenant_id, actor_id)
    return [ClaimResponse.model_validate(c) for c in claims]


@router.get("/{actor_id}/agencies", response_model=list[ActorAgencyLinkResponse])
async def list_actor_agencies(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    links = await ActorService.list_agency_links(db, current_user.tenant_id, actor_id)
    return [ActorAgencyLinkResponse.model_validate(l) for l in links]


@router.get("/{actor_id}/companies", response_model=list[ActorCompanyLinkResponse])
async def list_actor_companies(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    links = await ActorService.list_company_links(db, current_user.tenant_id, actor_id)
    return [ActorCompanyLinkResponse.model_validate(l) for l in links]
