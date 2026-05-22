"""
Proxy routes for the external CAT Dispatcher service.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.cat_dispatcher import (
    CatDispatcherAddressLookupRequest,
    CatDispatcherCommuneLookupRequest,
    CatDispatcherLookupResponse,
)
from app.services.cat_dispatcher_service import CatDispatcherService

router = APIRouter()


class CatDispatcherDispatchPayload(BaseModel):
    model_config = ConfigDict(extra="allow")


@router.post("/address-to-cat", response_model=CatDispatcherLookupResponse)
async def lookup_cat_by_address(
    payload: CatDispatcherAddressLookupRequest,
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
):
    request_payload = payload.model_dump(exclude_none=True)
    return await CatDispatcherService.lookup_by_address(db, request_payload)


@router.post("/get-cat-by-commune", response_model=CatDispatcherLookupResponse)
async def lookup_cat_by_commune(
    payload: CatDispatcherCommuneLookupRequest,
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
):
    return await CatDispatcherService.lookup_by_commune(
        db,
        payload.comune,
        payload.provincia,
    )


@router.get("/map-data")
async def get_cat_dispatcher_map_data(
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    return await CatDispatcherService.map_data(db)


@router.get("/search")
async def search_cat_dispatcher_locations(
    query: str = Query(..., min_length=2),
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    return await CatDispatcherService.search(db, query)


@router.get("/communes/{commune_id}")
async def get_cat_dispatcher_commune_details(
    commune_id: str,
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    return await CatDispatcherService.commune_details(db, commune_id)


@router.get("/dispatch/availability")
async def get_cat_dispatcher_availability(
    cat_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    return await CatDispatcherService.get_availability(db, cat_id)


@router.post("/dispatch/{action}")
async def call_cat_dispatcher_dispatch_action(
    action: str,
    payload: CatDispatcherDispatchPayload,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    return await CatDispatcherService.dispatch_action(
        db,
        current_user.tenant_id,
        action,
        payload.model_dump(exclude_none=True),
    )
