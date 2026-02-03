"""
Tasks routes
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User

router = APIRouter()


@router.get("/claims/{claim_id}/tasks")
async def get_claim_tasks(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get tasks for a claim"""
    # TODO: Implement
    return {"tasks": []}


@router.post("/claims/{claim_id}/tasks")
async def create_task(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Create a task for a claim"""
    # TODO: Implement
    return {"status": "not_implemented"}

