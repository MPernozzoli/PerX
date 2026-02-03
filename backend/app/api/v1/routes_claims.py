"""
Claims routes
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.services.claim_service import ClaimService
from app.services.state_service import StateService
from app.schemas.claim import (
    ClaimCreate, ClaimUpdate, ClaimResponse, ClaimListResponse,
    ClaimStateTransitionRequest, ClaimAssignmentRequest, ClaimEventResponse
)

router = APIRouter()


@router.post("", response_model=ClaimResponse, status_code=status.HTTP_201_CREATED)
async def create_claim(
    claim_data: ClaimCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Create a new claim"""
    claim = await ClaimService.create_claim(
        db, current_user.tenant_id, claim_data, current_user.id
    )
    return ClaimResponse.model_validate(claim)


@router.get("", response_model=ClaimListResponse)
async def list_claims(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    stato: str = Query(None),
    assignee_id: str = Query(None),
    search: str = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """List claims with filters and pagination"""
    skip = (page - 1) * page_size
    claims, total = await ClaimService.list_claims(
        db, current_user.tenant_id, skip, page_size, stato, assignee_id, search
    )
    return ClaimListResponse(
        items=[ClaimResponse.model_validate(c) for c in claims],
        total=total,
        page=page,
        page_size=page_size
    )


@router.get("/{claim_id}", response_model=ClaimResponse)
async def get_claim(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get a claim by ID"""
    claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return ClaimResponse.model_validate(claim)


@router.put("/{claim_id}", response_model=ClaimResponse)
async def update_claim(
    claim_id: str,
    claim_data: ClaimUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update a claim"""
    claim = await ClaimService.update_claim(
        db, current_user.tenant_id, claim_id, claim_data, current_user.id
    )
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return ClaimResponse.model_validate(claim)


@router.post("/{claim_id}/state-transitions")
async def transition_state(
    claim_id: str,
    transition: ClaimStateTransitionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Transition claim to new state"""
    success = await StateService.transition_state(
        db, current_user.tenant_id, claim_id,
        transition.from_state, transition.to_state,
        current_user.id, transition.reason, transition.payload
    )
    if not success:
        raise HTTPException(status_code=400, detail="Invalid state transition")
    return {"status": "success"}


@router.get("/{claim_id}/events", response_model=list[ClaimEventResponse])
async def get_claim_events(
    claim_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get timeline events for a claim"""
    from sqlalchemy import select
    from app.models.claim_event import ClaimEvent
    
    skip = (page - 1) * page_size
    result = await db.execute(
        select(ClaimEvent)
        .where(
            (ClaimEvent.claim_id == claim_id) &
            (ClaimEvent.tenant_id == current_user.tenant_id)
        )
        .order_by(ClaimEvent.event_time.desc())
        .offset(skip)
        .limit(page_size)
    )
    events = result.scalars().all()
    return [ClaimEventResponse.model_validate(e) for e in events]

