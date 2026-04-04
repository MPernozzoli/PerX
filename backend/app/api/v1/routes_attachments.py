"""
Attachment routes
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.attachment import Attachment
from app.models.email import Email
from app.models.user import User
from app.schemas.comms import AttachmentCreate, AttachmentListResponse, AttachmentResponse
from app.services.claim_service import ClaimService

router = APIRouter()


@router.get("", response_model=AttachmentListResponse)
async def list_attachments(
    claim_id: str | None = Query(None),
    email_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(Attachment).where(Attachment.tenant_id == current_user.tenant_id)

    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.where(Attachment.claim_id == claim.id)

    if email_id:
        query = query.where(Attachment.email_id == email_id)

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(Attachment.uploaded_at.desc()))
    items = result.scalars().all()
    return AttachmentListResponse(
        items=[AttachmentResponse.model_validate(item) for item in items],
        total=total,
    )


@router.post("", response_model=AttachmentResponse, status_code=status.HTTP_201_CREATED)
async def create_attachment(
    payload: AttachmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_pk = None
    if payload.claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        claim_pk = claim.id

    if payload.email_id:
        email_result = await db.execute(
            select(Email).where(
                Email.id == payload.email_id,
                Email.tenant_id == current_user.tenant_id,
            )
        )
        if not email_result.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Email not found")

    attachment = Attachment(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        email_id=payload.email_id,
        claim_id=claim_pk,
        file_name=payload.file_name,
        mime_type=payload.mime_type,
        size_bytes=payload.size_bytes,
        storage_bucket=payload.storage_bucket,
        storage_path=payload.storage_path,
        checksum=payload.checksum,
        uploaded_by_user_id=current_user.id,
    )
    db.add(attachment)
    await db.commit()
    await db.refresh(attachment)
    return AttachmentResponse.model_validate(attachment)


@router.post("/claims/{claim_id}/attachments/upload-url")
async def get_upload_url(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get pre-signed URL for direct upload"""
    # TODO: Implement with GCS/S3
    return {"upload_url": "", "expires_in": 3600}
