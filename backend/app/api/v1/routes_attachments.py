"""
Attachment routes
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User

router = APIRouter()


@router.post("/claims/{claim_id}/attachments/upload-url")
async def get_upload_url(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get pre-signed URL for direct upload"""
    # TODO: Implement with GCS/S3
    return {"upload_url": "", "expires_in": 3600}

