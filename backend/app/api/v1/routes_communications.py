"""
Unified communications routes.
"""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.communication import Call, CallParticipant, CommunicationSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.communication import (
    CommunicationResolveRequest,
    CommunicationResolutionResponse,
    CommunicationLiveKitTokenResponse,
    CommunicationSessionActionRequest,
    CommunicationSessionActionResponse,
    CommunicationStartRequest,
    CommunicationStartResponse,
    CommunicationIncomingCallListResponse,
    ExternalInviteCreateRequest,
    ExternalInviteResponse,
    ExtensionAssignRequest,
    ExtensionDisableRequest,
    ExtensionLookupResponse,
    ProviderWebhookRequest,
    ProviderWebhookResponse,
    ScheduledCommunicationCreateRequest,
    ScheduledCommunicationResponse,
)
from app.services.communication_destination_resolver import CommunicationDestinationResolver
from app.services.communication_extension_service import (
    CommunicationExtensionService,
    ExtensionUnavailableError,
)
from app.services.communication_service import CommunicationService
from app.services.livekit_token_service import LiveKitNotConfiguredError

router = APIRouter()


class CallHistoryItem(BaseModel):
    id: str
    display_name: Optional[str] = None
    state: str
    destination_type: str
    transport: str
    direction: Optional[str] = None
    from_value: Optional[str] = None
    to_value: Optional[str] = None
    claim_id: Optional[str] = None
    created_at: datetime
    ended_at: Optional[datetime] = None


class CallHistoryListResponse(BaseModel):
    items: list[CallHistoryItem]
    total: int


@router.get("/sessions", response_model=CallHistoryListResponse)
async def list_call_sessions(
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """
    Recent communication sessions involving the current user — as caller,
    callee, or creator. Newest first. Includes ended calls.
    """
    query = (
        select(CommunicationSession, Call)
        .outerjoin(Call, Call.session_id == CommunicationSession.id)
        .outerjoin(CallParticipant, CallParticipant.session_id == CommunicationSession.id)
        .where(
            CommunicationSession.tenant_id == current_user.tenant_id,
            or_(
                CommunicationSession.created_by_user_id == current_user.id,
                CallParticipant.user_id == current_user.id,
            ),
        )
        .order_by(CommunicationSession.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(query)
    rows = result.all()
    seen: set[str] = set()
    items: list[CallHistoryItem] = []
    for session, call in rows:
        if session.id in seen:
            continue
        seen.add(session.id)
        items.append(CallHistoryItem(
            id=session.id,
            display_name=session.display_name,
            state=session.state,
            destination_type=session.destination_type,
            transport=session.transport,
            direction=getattr(call, "direction", None),
            from_value=getattr(call, "from_value", None),
            to_value=getattr(call, "to_value", None),
            claim_id=session.claim_id,
            created_at=session.created_at,
            ended_at=session.ended_at,
        ))
    return CallHistoryListResponse(items=items, total=len(items))


@router.post("/resolve", response_model=CommunicationResolutionResponse)
async def resolve_destination(
    payload: CommunicationResolveRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    ctx_tenant = payload.context.tenant_id
    if ctx_tenant in (None, "", "default"):
        ctx_tenant = current_user.tenant_id
    tenant_id = ctx_tenant
    if tenant_id != current_user.tenant_id:
        # TODO(inter-tenant): replace with explicit cross-tenant invitation auth.
        raise HTTPException(status_code=403, detail="Cross-tenant communication is not enabled")
    return await CommunicationDestinationResolver().resolve(
        db=db,
        tenant_id=current_user.tenant_id,
        raw_destination=payload.destination,
        context=payload.context,
    )


@router.post("/start", response_model=CommunicationStartResponse)
async def start_communication(
    payload: CommunicationStartRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    # Client UI seeds destination.tenant_id as the placeholder "default" because it
    # doesn't know the authenticated user's real tenant. Normalize that case to the
    # current user's tenant rather than rejecting as cross-tenant.
    if payload.destination.tenant_id in (None, "", "default"):
        payload.destination.tenant_id = current_user.tenant_id
    if not payload.destination.display_name:
        payload.destination.display_name = payload.destination.raw_value
    if payload.destination.tenant_id != current_user.tenant_id:
        # TODO(inter-tenant): future LiveKit federation must require explicit grants,
        # tenant-separated audit, and no implicit user discovery.
        raise HTTPException(status_code=403, detail="Cross-tenant communication is not enabled")
    try:
        return await CommunicationService().start_communication(
            db=db,
            current_user=current_user,
            destination=payload.destination,
            context=payload.context,
        )
    except LiveKitNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/sessions/{session_id}/livekit-token", response_model=CommunicationLiveKitTokenResponse)
async def mint_livekit_token(
    session_id: str,
    call_id: str | None = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        return await CommunicationService().mint_livekit_token(
            db=db,
            current_user=current_user,
            session_id=session_id,
            call_id=call_id,
        )
    except LiveKitNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/incoming", response_model=CommunicationIncomingCallListResponse)
async def list_incoming_calls(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    return await CommunicationService().list_incoming_calls(db, current_user)


@router.post("/sessions/{session_id}/actions", response_model=CommunicationSessionActionResponse)
async def handle_session_action(
    session_id: str,
    payload: CommunicationSessionActionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        return await CommunicationService().handle_session_action(
            db=db,
            current_user=current_user,
            session_id=session_id,
            action_type=payload.action_type,
        )
    except LiveKitNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/provider-webhook", response_model=ProviderWebhookResponse)
async def provider_webhook(
    payload: ProviderWebhookRequest,
    db: AsyncSession = Depends(get_db),
):
    return await CommunicationService().handle_provider_webhook(
        db=db,
        provider=payload.provider,
        headers=payload.headers,
        payload=payload.payload,
        tenant_id=payload.tenant_id,
    )


@router.post("/scheduled", response_model=ScheduledCommunicationResponse)
async def create_scheduled_communication(
    payload: ScheduledCommunicationCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=400, detail="ends_at must be after starts_at")
    return await CommunicationService().create_scheduled_communication(db, current_user, payload)


@router.post("/invite-links", response_model=ExternalInviteResponse)
async def create_external_invite_link(
    payload: ExternalInviteCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if payload.valid_until <= payload.valid_from:
        raise HTTPException(status_code=400, detail="valid_until must be after valid_from")
    if not payload.session_id and not payload.scheduled_communication_id:
        raise HTTPException(status_code=400, detail="session_id or scheduled_communication_id is required")
    return await CommunicationService().create_external_invite(db, current_user, payload)


@router.post("/extensions/assign", response_model=ExtensionLookupResponse)
async def assign_extension(
    payload: ExtensionAssignRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    user = await _tenant_user(db, current_user, payload.user_id)
    try:
        await CommunicationExtensionService.assign_extension(
            db,
            user,
            extension_number=payload.extension_number,
            display_name=payload.display_name,
        )
    except (ValueError, ExtensionUnavailableError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    await db.commit()
    await db.refresh(user)
    return _extension_response(user)


@router.post("/extensions/disable", response_model=ExtensionLookupResponse)
async def disable_extension(
    payload: ExtensionDisableRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    user = await _tenant_user(db, current_user, payload.user_id)
    await CommunicationExtensionService.disable_extension(db, user)
    await db.commit()
    await db.refresh(user)
    return _extension_response(user)


@router.get("/extensions/{extension_number}", response_model=ExtensionLookupResponse)
async def lookup_extension(
    extension_number: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        user = await CommunicationExtensionService.find_user_by_extension(
            db,
            current_user.tenant_id,
            extension_number,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if user is None:
        raise HTTPException(status_code=404, detail="Extension not found")
    return _extension_response(user)


async def _tenant_user(db: AsyncSession, current_user: User, user_id: str) -> User:
    result = await db.execute(
        select(User).where(
            User.id == user_id,
            User.tenant_id == current_user.tenant_id,
            User.is_active == True,
        )
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def _extension_response(user: User) -> ExtensionLookupResponse:
    return ExtensionLookupResponse(
        user_id=user.id,
        tenant_id=user.tenant_id,
        extension_number=user.extension_number or "",
        display_name=user.extension_display_name or user.full_name,
        availability_status=user.availability_status or "available",
        communication_status=user.communication_status or "idle",
    )
