"""
Sinistro folder package routes
Handles ZIP folder requests: iPad creates a request, Mac polls, processes, and marks ready.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.folder_request import SinistroFolderRequest
from app.models.user import User
from app.schemas.folder_package import (
    FolderRequestCreate,
    FolderRequestListResponse,
    FolderRequestReadyUpdate,
    FolderRequestResponse,
    FolderRequestStatusUpdate,
)

router = APIRouter()

VALID_STATUSES = {"pending", "processing", "ready", "error"}


@router.post("/request", response_model=FolderRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_folder_request(
    payload: FolderRequestCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    req = SinistroFolderRequest(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=payload.claim_id,
        riferimento=payload.riferimento,
        requested_by_user_id=current_user.id,
        status="pending",
    )
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return FolderRequestResponse.model_validate(req)


@router.get("/requests", response_model=FolderRequestListResponse)
async def list_folder_requests(
    status_filter: str | None = Query(None, alias="status"),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(SinistroFolderRequest).where(
        SinistroFolderRequest.tenant_id == current_user.tenant_id
    )
    if status_filter:
        query = query.where(SinistroFolderRequest.status == status_filter)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(
        query.order_by(SinistroFolderRequest.created_at.desc()).offset(skip).limit(limit)
    )
    items = result.scalars().all()
    return FolderRequestListResponse(items=[FolderRequestResponse.model_validate(i) for i in items], total=total)


@router.get("/requests/{request_id}", response_model=FolderRequestResponse)
async def get_folder_request(
    request_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(SinistroFolderRequest).where(
            SinistroFolderRequest.id == request_id,
            SinistroFolderRequest.tenant_id == current_user.tenant_id,
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Folder request not found")
    return FolderRequestResponse.model_validate(req)


@router.put("/requests/{request_id}/status", response_model=FolderRequestResponse)
async def update_folder_request_status(
    request_id: str,
    payload: FolderRequestStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Mac client updates the processing status of a request."""
    if payload.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {', '.join(VALID_STATUSES)}")

    result = await db.execute(
        select(SinistroFolderRequest).where(
            SinistroFolderRequest.id == request_id,
            SinistroFolderRequest.tenant_id == current_user.tenant_id,
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Folder request not found")

    req.status = payload.status
    if payload.error_message is not None:
        req.error_message = payload.error_message
    if payload.status in ("ready", "error"):
        req.completed_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(req)
    return FolderRequestResponse.model_validate(req)


@router.put("/requests/{request_id}/ready", response_model=FolderRequestResponse)
async def mark_folder_request_ready(
    request_id: str,
    payload: FolderRequestReadyUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Mac client sets download_url once ZIP is ready in Supabase Storage."""
    result = await db.execute(
        select(SinistroFolderRequest).where(
            SinistroFolderRequest.id == request_id,
            SinistroFolderRequest.tenant_id == current_user.tenant_id,
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Folder request not found")

    req.status = "ready"
    req.download_url = payload.download_url
    req.completed_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(req)

    # Broadcast folder_ready event via SSE
    try:
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(
            current_user.tenant_id,
            "folder_ready",
            {
                "request_id": req.id,
                "riferimento": req.riferimento,
                "claim_id": req.claim_id,
                "download_url": req.download_url,
            },
        )
    except Exception:
        pass  # SSE broadcast is best-effort

    return FolderRequestResponse.model_validate(req)
