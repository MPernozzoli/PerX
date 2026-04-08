"""
Internal chat routes
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim_event import ClaimEvent
from app.models.internal_chat import InternalChatMember, InternalChatMessage, InternalChatThread
from app.models.user import User
from app.schemas.collab import (
    InternalChatMessageCreate,
    InternalChatMessageListResponse,
    InternalChatMessageResponse,
    InternalChatThreadCreate,
    InternalChatThreadListResponse,
    InternalChatThreadResponse,
)
from app.services.claim_service import ClaimService

router = APIRouter()


@router.get("/threads", response_model=InternalChatThreadListResponse)
async def list_threads(
    claim_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = (
        select(InternalChatThread)
        .join(InternalChatMember, InternalChatMember.thread_id == InternalChatThread.id)
        .where(
            InternalChatThread.tenant_id == current_user.tenant_id,
            InternalChatMember.user_id == current_user.id,
        )
    )
    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.where(InternalChatThread.claim_id == claim.id)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(InternalChatThread.created_at.desc()))
    items = result.scalars().all()
    return InternalChatThreadListResponse(items=[InternalChatThreadResponse.model_validate(i) for i in items], total=total)


@router.post("/threads", response_model=InternalChatThreadResponse, status_code=status.HTTP_201_CREATED)
async def create_thread(
    payload: InternalChatThreadCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_pk = None
    if payload.claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        claim_pk = claim.id

    thread = InternalChatThread(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_pk,
        title=payload.title,
        thread_type=payload.thread_type,
        created_by_user_id=current_user.id,
        metadata_json=payload.metadata_json,
    )
    db.add(thread)
    db.add(InternalChatMember(thread_id=thread.id, user_id=current_user.id))

    if payload.member_user_ids:
        result = await db.execute(
            select(User.id).where(
                User.tenant_id == current_user.tenant_id,
                User.id.in_(payload.member_user_ids),
            )
        )
        for (user_id,) in result.all():
            if user_id != current_user.id:
                db.add(InternalChatMember(thread_id=thread.id, user_id=user_id))

    await db.commit()
    await db.refresh(thread)
    return InternalChatThreadResponse.model_validate(thread)


@router.get("/threads/{thread_id}/messages", response_model=InternalChatMessageListResponse)
async def list_messages(
    thread_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    member = await db.execute(
        select(InternalChatMember).where(
            InternalChatMember.thread_id == thread_id,
            InternalChatMember.user_id == current_user.id,
        )
    )
    if not member.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Thread not found")

    query = select(InternalChatMessage).where(
        InternalChatMessage.thread_id == thread_id,
        InternalChatMessage.tenant_id == current_user.tenant_id,
    )
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(InternalChatMessage.created_at.asc()))
    items = result.scalars().all()
    return InternalChatMessageListResponse(items=[InternalChatMessageResponse.model_validate(i) for i in items], total=total)


@router.post("/threads/{thread_id}/messages", response_model=InternalChatMessageResponse, status_code=status.HTTP_201_CREATED)
async def create_message(
    thread_id: str,
    payload: InternalChatMessageCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    thread_result = await db.execute(
        select(InternalChatThread)
        .join(InternalChatMember, InternalChatMember.thread_id == InternalChatThread.id)
        .where(
            InternalChatThread.id == thread_id,
            InternalChatThread.tenant_id == current_user.tenant_id,
            InternalChatMember.user_id == current_user.id,
        )
    )
    thread = thread_result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Thread not found")

    message = InternalChatMessage(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        thread_id=thread.id,
        claim_id=thread.claim_id,
        sender_user_id=current_user.id,
        body_text=payload.body_text,
        message_type=payload.message_type,
        attachment_document_id=payload.attachment_document_id,
        metadata_json=payload.metadata_json,
    )
    db.add(message)
    if thread.claim_id:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=current_user.tenant_id,
                claim_id=thread.claim_id,
                event_type="internal_chat_message",
                actor_user_id=current_user.id,
                data_json={"thread_id": thread.id, "message_id": message.id},
                source="chat",
            )
        )
    await db.commit()
    await db.refresh(message)
    return InternalChatMessageResponse.model_validate(message)
