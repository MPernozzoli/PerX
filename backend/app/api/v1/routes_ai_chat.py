"""
AI chat routes
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.ai_chat import AIChatMessage, AIChatSession
from app.models.user import User
from app.schemas.collab import (
    AIChatMessageCreate,
    AIChatMessageListResponse,
    AIChatMessageResponse,
    AIChatSessionCreate,
    AIChatSessionListResponse,
    AIChatSessionResponse,
)
from app.services.claim_service import ClaimService

router = APIRouter()


@router.get("/sessions", response_model=AIChatSessionListResponse)
async def list_sessions(
    claim_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(AIChatSession).where(
        AIChatSession.tenant_id == current_user.tenant_id,
        AIChatSession.user_id == current_user.id,
    )
    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.where(AIChatSession.claim_id == claim.id)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(AIChatSession.updated_at.desc()))
    items = result.scalars().all()
    return AIChatSessionListResponse(items=[AIChatSessionResponse.model_validate(i) for i in items], total=total)


@router.post("/sessions", response_model=AIChatSessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    payload: AIChatSessionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_pk = None
    if payload.claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        claim_pk = claim.id

    session = AIChatSession(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_pk,
        user_id=current_user.id,
        title=payload.title,
        model=payload.model,
        context_json=payload.context_json,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return AIChatSessionResponse.model_validate(session)


@router.get("/sessions/{session_id}/messages", response_model=AIChatMessageListResponse)
async def list_messages(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    session_result = await db.execute(
        select(AIChatSession).where(
            AIChatSession.id == session_id,
            AIChatSession.tenant_id == current_user.tenant_id,
            AIChatSession.user_id == current_user.id,
        )
    )
    session = session_result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="AI session not found")

    query = select(AIChatMessage).where(
        AIChatMessage.session_id == session.id,
        AIChatMessage.tenant_id == current_user.tenant_id,
    )
    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(AIChatMessage.created_at.asc()))
    items = result.scalars().all()
    return AIChatMessageListResponse(items=[AIChatMessageResponse.model_validate(i) for i in items], total=total)


@router.post("/sessions/{session_id}/messages", response_model=AIChatMessageResponse, status_code=status.HTTP_201_CREATED)
async def create_message(
    session_id: str,
    payload: AIChatMessageCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    session_result = await db.execute(
        select(AIChatSession).where(
            AIChatSession.id == session_id,
            AIChatSession.tenant_id == current_user.tenant_id,
            AIChatSession.user_id == current_user.id,
        )
    )
    session = session_result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="AI session not found")

    message = AIChatMessage(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        session_id=session.id,
        role=payload.role,
        body_text=payload.body_text,
        payload_json=payload.payload_json,
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    return AIChatMessageResponse.model_validate(message)
