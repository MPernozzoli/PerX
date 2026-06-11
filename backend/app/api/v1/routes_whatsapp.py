"""
WhatsApp routes
"""
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim_event import ClaimEvent
from app.models.user import User
from app.models.whatsapp import WhatsAppMessage, WhatsAppThread
from app.schemas.comms import (
    WhatsAppMessageCreate,
    WhatsAppMessageListResponse,
    WhatsAppMessageResponse,
    WhatsAppThreadCreate,
    WhatsAppThreadListResponse,
    WhatsAppThreadResponse,
)
from app.services.claim_service import ClaimService

router = APIRouter()


@router.get("/threads", response_model=WhatsAppThreadListResponse)
async def list_threads(
    claim_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(WhatsAppThread).where(WhatsAppThread.tenant_id == current_user.tenant_id)
    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.where(WhatsAppThread.claim_id == claim.id)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(WhatsAppThread.last_message_at.desc().nullslast(), WhatsAppThread.created_at.desc()))
    items = result.scalars().all()
    return WhatsAppThreadListResponse(
        items=[WhatsAppThreadResponse.model_validate(item) for item in items],
        total=total,
    )


@router.post("/threads", response_model=WhatsAppThreadResponse, status_code=status.HTTP_201_CREATED)
async def create_thread(
    payload: WhatsAppThreadCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_pk = None
    if payload.claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        claim_pk = claim.id

    thread = WhatsAppThread(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_pk,
        account_id=payload.account_id,
        external_thread_ref=payload.external_thread_ref,
        contact_name=payload.contact_name,
        contact_phone=payload.contact_phone,
        status=payload.status,
        metadata_json=payload.metadata_json,
    )
    db.add(thread)
    await db.commit()
    await db.refresh(thread)
    return WhatsAppThreadResponse.model_validate(thread)


@router.get("/threads/{thread_id}/messages", response_model=WhatsAppMessageListResponse)
async def list_messages(
    thread_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    thread_result = await db.execute(
        select(WhatsAppThread).where(
            WhatsAppThread.id == thread_id,
            WhatsAppThread.tenant_id == current_user.tenant_id,
        )
    )
    thread = thread_result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    query = select(WhatsAppMessage).where(
        WhatsAppMessage.thread_id == thread.id,
        WhatsAppMessage.tenant_id == current_user.tenant_id,
    )
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(WhatsAppMessage.sent_at.asc()))
    items = result.scalars().all()
    return WhatsAppMessageListResponse(
        items=[WhatsAppMessageResponse.model_validate(item) for item in items],
        total=total,
    )


@router.post("/messages", response_model=WhatsAppMessageResponse, status_code=status.HTTP_201_CREATED)
async def create_message(
    payload: WhatsAppMessageCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    thread_result = await db.execute(
        select(WhatsAppThread).where(
            WhatsAppThread.id == payload.thread_id,
            WhatsAppThread.tenant_id == current_user.tenant_id,
        )
    )
    thread = thread_result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    message = WhatsAppMessage(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        thread_id=thread.id,
        claim_id=thread.claim_id,
        direction=payload.direction,
        message_type=payload.message_type,
        provider_message_id=payload.provider_message_id,
        sender_user_id=current_user.id if payload.direction == "outbound" else None,
        sender_label=payload.sender_label,
        body_text=payload.body_text,
        media_document_id=payload.media_document_id,
        sent_at=payload.sent_at or datetime.utcnow(),
        status=payload.status,
        metadata_json=payload.metadata_json,
    )
    db.add(message)
    thread.last_message_at = message.sent_at
    if payload.direction == "inbound" and thread.claim_id:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=current_user.tenant_id,
                claim_id=thread.claim_id,
                event_type="whatsapp_message",
                actor_user_id=current_user.id,
                data_json={"thread_id": thread.id, "message_id": message.id, "direction": message.direction},
                source="whatsapp",
            )
        )
    await db.commit()
    await db.refresh(message)
    response = WhatsAppMessageResponse.model_validate(message)
    try:
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(
            current_user.tenant_id,
            "wa_message",
            {
                "thread_id": thread.id,
                "message_id": message.id,
                "direction": message.direction,
                "claim_id": thread.claim_id,
            },
        )
    except Exception:
        pass
    return response
