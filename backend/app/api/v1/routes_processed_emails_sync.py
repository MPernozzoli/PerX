"""
Processed emails sync routes
Stores processed email message_ids in user_settings JSON under key "processed_email_ids".
"""
import uuid
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.models.user_settings import UserSettings

router = APIRouter()

PROCESSED_EMAILS_KEY = "processed_email_ids"


class ProcessedEmailEntry(BaseModel):
    message_id: str
    processed_at: str | None = None  # ISO8601 string, informational only


class ProcessedEmailBatch(BaseModel):
    items: List[ProcessedEmailEntry]


class ProcessedEmailsResponse(BaseModel):
    message_ids: List[str]
    total: int


async def _get_or_create_user_settings(db: AsyncSession, user: User) -> UserSettings:
    result = await db.execute(select(UserSettings).where(UserSettings.user_id == user.id))
    settings = result.scalar_one_or_none()
    if not settings:
        settings = UserSettings(
            id=str(uuid.uuid4()),
            user_id=user.id,
            tenant_id=user.tenant_id,
            settings_json={},
        )
        db.add(settings)
        await db.flush()
    return settings


@router.get("/", response_model=ProcessedEmailsResponse)
async def get_processed_emails(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Return all processed message_ids for the current user."""
    settings = await _get_or_create_user_settings(db, current_user)
    await db.commit()
    ids: List[str] = list(settings.settings_json.get(PROCESSED_EMAILS_KEY, []) if settings.settings_json else [])
    return ProcessedEmailsResponse(message_ids=ids, total=len(ids))


@router.post("/batch", response_model=ProcessedEmailsResponse)
async def upsert_processed_emails(
    payload: ProcessedEmailBatch,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Upsert a batch of processed message_ids into the user's settings."""
    settings = await _get_or_create_user_settings(db, current_user)
    current_json = dict(settings.settings_json or {})
    existing: List[str] = list(current_json.get(PROCESSED_EMAILS_KEY, []))

    incoming_ids = {entry.message_id for entry in payload.items}
    merged = list(dict.fromkeys(existing + list(incoming_ids)))  # preserve order, deduplicate

    current_json[PROCESSED_EMAILS_KEY] = merged
    settings.settings_json = current_json

    await db.commit()
    await db.refresh(settings)

    ids: List[str] = list(settings.settings_json.get(PROCESSED_EMAILS_KEY, []))
    return ProcessedEmailsResponse(message_ids=ids, total=len(ids))
