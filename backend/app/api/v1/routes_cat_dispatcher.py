"""
Proxy routes for the external CAT Dispatcher service.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.cat_dispatcher import (
    CatDispatcherAddressLookupRequest,
    CatDispatcherCommuneLookupRequest,
    CatDispatcherLookupResponse,
)
from app.services.cat_dispatcher_service import CatDispatcherService

router = APIRouter()


@router.post("/address-to-cat", response_model=CatDispatcherLookupResponse)
async def lookup_cat_by_address(
    payload: CatDispatcherAddressLookupRequest,
    _current_user: User = Depends(get_current_active_user),
):
    request_payload = payload.model_dump(exclude_none=True)
    return await CatDispatcherService.post("address-to-cat", request_payload)


@router.post("/get-cat-by-commune", response_model=CatDispatcherLookupResponse)
async def lookup_cat_by_commune(
    payload: CatDispatcherCommuneLookupRequest,
    _current_user: User = Depends(get_current_active_user),
):
    request_payload = payload.model_dump(exclude_none=True)
    return await CatDispatcherService.post("get-cat-by-commune", request_payload)
