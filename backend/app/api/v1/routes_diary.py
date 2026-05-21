"""
Claim diary routes
"""
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim_diary_entry import ClaimDiaryEntry
from app.models.user import User
from app.schemas.content import (
    ClaimDiaryEntryCreate,
    ClaimDiaryEntryListResponse,
    ClaimDiaryEntryResponse,
)
from app.services.claim_service import ClaimService
from app.services.automation_service import AutomationService

router = APIRouter()


async def _resolve_claim_or_404(
    db: AsyncSession,
    current_user: User,
    claim_identifier: str,
):
    claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_identifier)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return claim


@router.get("/claims/{claim_id}/diary", response_model=ClaimDiaryEntryListResponse)
async def list_claim_diary(
    claim_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, claim_id)
    query = select(ClaimDiaryEntry).where(
        ClaimDiaryEntry.tenant_id == current_user.tenant_id,
        ClaimDiaryEntry.claim_id == claim.id,
    )

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(
        query.order_by(ClaimDiaryEntry.happened_at.desc(), ClaimDiaryEntry.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    items = result.scalars().all()
    return ClaimDiaryEntryListResponse(
        items=[ClaimDiaryEntryResponse.model_validate(item) for item in items],
        total=total,
    )


@router.post(
    "/claims/{claim_id}/diary",
    response_model=ClaimDiaryEntryResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_claim_diary_entry(
    claim_id: str,
    payload: ClaimDiaryEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, claim_id)
    entry = ClaimDiaryEntry(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        entry_type=payload.entry_type,
        title=payload.title,
        body_text=payload.body_text,
        visibility=payload.visibility,
        happened_at=payload.happened_at or datetime.utcnow(),
        created_by_user_id=current_user.id,
        metadata_json=payload.metadata_json,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)

    await ClaimService._create_event(
        db,
        current_user.tenant_id,
        claim.id,
        "diary_entry_created",
        current_user.id,
        {"entry_id": entry.id, "entry_type": entry.entry_type, "title": entry.title},
    )

    await AutomationService.process_diary_entry(
        db,
        current_user.tenant_id,
        claim,
        entry,
        current_user.id,
    )

    return ClaimDiaryEntryResponse.model_validate(entry)
