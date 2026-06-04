"""
Videoperizia live-session endpoints (expert app side).

Lifecycle:
    POST /claims/{claim_id}/videoperizia/session       — create or fetch
    POST /claims/{claim_id}/videoperizia/session/{sid}/start  — go live
    POST /claims/{claim_id}/videoperizia/session/{sid}/end    — close + handoff
    GET  /claims/{claim_id}/videoperizia/session/{sid}        — snapshot
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.videoperizia import (
    VideoperiziaEndResponse,
    VideoperiziaLocationPingListResponse,
    VideoperiziaLocationPingResponse,
    VideoperiziaMediaListResponse,
    VideoperiziaMediaResponse,
    VideoperiziaOutcomeRequest,
    VideoperiziaSessionCreateResponse,
    VideoperiziaSessionEndRequest,
    VideoperiziaSessionResponse,
    VideoperiziaTokenResponse,
)
from app.services.livekit_token_service import (
    LiveKitGrant,
    LiveKitNotConfiguredError,
    LiveKitTokenService,
)
from app.services.supabase_storage_service import SupabaseStorageService
from app.services.videoperizia_session_service import VideoperiziaSessionService

router = APIRouter()


def _tenant_id(current_user: User) -> str:
    return current_user.tenant_id


@router.post(
    "/claims/{claim_id}/videoperizia/session",
    response_model=VideoperiziaSessionCreateResponse,
)
async def create_or_fetch_session(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaSessionCreateResponse:
    try:
        session = await VideoperiziaSessionService.create_or_get(db, _tenant_id(current_user), claim_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return VideoperiziaSessionCreateResponse(
        session=VideoperiziaSessionResponse.model_validate(session),
    )


@router.post(
    "/claims/{claim_id}/videoperizia/session/{session_id}/start",
    response_model=VideoperiziaSessionResponse,
)
async def start_session(
    claim_id: str,
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaSessionResponse:
    try:
        session = await VideoperiziaSessionService.start(
            db, _tenant_id(current_user), claim_id, session_id,
            perito_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return VideoperiziaSessionResponse.model_validate(session)


@router.post(
    "/claims/{claim_id}/videoperizia/session/{session_id}/end",
    response_model=VideoperiziaEndResponse,
)
async def end_session(
    claim_id: str,
    session_id: str,
    payload: VideoperiziaSessionEndRequest = VideoperiziaSessionEndRequest(),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaEndResponse:
    try:
        session, needs_confirmation, frame_count = await VideoperiziaSessionService.end(
            db, _tenant_id(current_user), claim_id, session_id,
            ended_by_user_id=current_user.id,
            reason=payload.reason,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return VideoperiziaEndResponse(
        session=VideoperiziaSessionResponse.model_validate(session),
        needs_outcome_confirmation=needs_confirmation,
        frame_count=frame_count,
    )


@router.post(
    "/claims/{claim_id}/videoperizia/session/{session_id}/outcome",
    response_model=VideoperiziaSessionResponse,
)
async def submit_outcome(
    claim_id: str,
    session_id: str,
    payload: VideoperiziaOutcomeRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaSessionResponse:
    """
    Submit the expert's manual outcome for a low-evidence session.

    Called only when end_session returned needs_outcome_confirmation=True.
    Allowed outcomes:
      - confirmed            → claim → DA_GESTIRE_VIDEO
      - reschedule_video     → claim stays VIDEOPERIZIA, resets to da_fissare
      - escalate_sopralluogo → claim → SOPRALLUOGO da_fissare
    """
    try:
        session = await VideoperiziaSessionService.submit_outcome(
            db, _tenant_id(current_user), claim_id, session_id,
            outcome=payload.outcome,
            user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return VideoperiziaSessionResponse.model_validate(session)


@router.post(
    "/claims/{claim_id}/videoperizia/session/{session_id}/token",
    response_model=VideoperiziaTokenResponse,
)
async def mint_perito_token(
    claim_id: str,
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaTokenResponse:
    """
    Mint a LiveKit token for the expert. Publish is always granted: the perito
    is in control of the call. Token TTL is short-lived; clients refresh on
    reconnect.
    """
    try:
        session = await VideoperiziaSessionService.get(db, _tenant_id(current_user), claim_id, session_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if session.state in ("ended", "aborted"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Session is closed")

    grant = LiveKitGrant(can_subscribe=True, can_publish=True, can_publish_data=True)
    try:
        minted = LiveKitTokenService.mint(
            identity=f"perito:{current_user.id}",
            room_name=session.livekit_room_name,
            grant=grant,
            display_name=current_user.full_name or current_user.email,
            metadata={"role": "perito", "user_id": current_user.id, "session_id": session.id},
        )
    except LiveKitNotConfiguredError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))

    return VideoperiziaTokenResponse(
        token=minted.token,
        livekit_url=minted.livekit_url,
        room_name=minted.room_name,
        identity=minted.identity,
        expires_at=minted.expires_at,
        can_publish=grant.can_publish,
        can_subscribe=grant.can_subscribe,
        session=VideoperiziaSessionResponse.model_validate(session),
    )


@router.post(
    "/claims/{claim_id}/videoperizia/session/{session_id}/media",
    response_model=VideoperiziaMediaResponse,
)
async def upload_media(
    claim_id: str,
    session_id: str,
    kind: str = Form(..., description="frame | clip"),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaMediaResponse:
    content = await file.read()
    try:
        media = await VideoperiziaSessionService.record_media(
            db, _tenant_id(current_user), claim_id, session_id,
            kind=kind,
            content=content,
            mime_type=file.content_type,
            original_filename=file.filename,
            captured_by_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return await _to_media_response(media)


@router.get(
    "/claims/{claim_id}/videoperizia/session/{session_id}/media",
    response_model=VideoperiziaMediaListResponse,
)
async def list_media(
    claim_id: str,
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaMediaListResponse:
    rows = await VideoperiziaSessionService.list_media(
        db, _tenant_id(current_user), claim_id, session_id=session_id
    )
    items = [await _to_media_response(row) for row in rows]
    return VideoperiziaMediaListResponse(items=items)


@router.get(
    "/claims/{claim_id}/videoperizia/session/{session_id}/location-pings",
    response_model=VideoperiziaLocationPingListResponse,
)
async def list_location_pings(
    claim_id: str,
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaLocationPingListResponse:
    rows = await VideoperiziaSessionService.list_location_pings(
        db, _tenant_id(current_user), claim_id, session_id=session_id
    )
    return VideoperiziaLocationPingListResponse(
        items=[VideoperiziaLocationPingResponse.model_validate(row) for row in rows],
    )


async def _to_media_response(media) -> VideoperiziaMediaResponse:
    signed_url = None
    if SupabaseStorageService.is_configured():
        try:
            signed_url = await SupabaseStorageService.create_signed_url(
                media.storage_path, expires_in_seconds=3600
            )
        except Exception:
            signed_url = None
    response = VideoperiziaMediaResponse.model_validate(media)
    return response.model_copy(update={"signed_url": signed_url})


@router.get(
    "/claims/{claim_id}/videoperizia/session/{session_id}",
    response_model=VideoperiziaSessionResponse,
)
async def get_session(
    claim_id: str,
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> VideoperiziaSessionResponse:
    try:
        session = await VideoperiziaSessionService.get(db, _tenant_id(current_user), claim_id, session_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return VideoperiziaSessionResponse.model_validate(session)
