"""
User settings and shared (tenant-level) settings routes
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.models.user_settings import SharedSettings, UserSettings
from app.schemas.user_settings import (
    SharedSettingsPatch,
    SharedSettingsResponse,
    UserSettingsPatch,
    UserSettingsResponse,
)

router = APIRouter()


async def _get_or_create_user_settings(db: AsyncSession, user: User) -> UserSettings:
    result = await db.execute(
        select(UserSettings).where(UserSettings.user_id == user.id)
    )
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


async def _get_or_create_shared_settings(db: AsyncSession, tenant_id: str) -> SharedSettings:
    result = await db.execute(
        select(SharedSettings).where(SharedSettings.tenant_id == tenant_id)
    )
    settings = result.scalar_one_or_none()
    if not settings:
        settings = SharedSettings(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            settings_json={},
        )
        db.add(settings)
        await db.flush()
    return settings


@router.get("/user", response_model=UserSettingsResponse)
async def get_user_settings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    settings = await _get_or_create_user_settings(db, current_user)
    await db.commit()
    await db.refresh(settings)
    return UserSettingsResponse(
        user_id=settings.user_id,
        tenant_id=settings.tenant_id,
        settings_json=settings.settings_json or {},
        updated_at=settings.updated_at,
    )


@router.put("/user", response_model=UserSettingsResponse)
async def update_user_settings(
    payload: UserSettingsPatch,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Merge-patch: merges top-level keys from payload.settings into existing settings_json."""
    settings = await _get_or_create_user_settings(db, current_user)
    current = dict(settings.settings_json or {})
    current.update(payload.settings)
    settings.settings_json = current
    settings.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(settings)
    return UserSettingsResponse(
        user_id=settings.user_id,
        tenant_id=settings.tenant_id,
        settings_json=settings.settings_json or {},
        updated_at=settings.updated_at,
    )


@router.get("/shared", response_model=SharedSettingsResponse)
async def get_shared_settings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    settings = await _get_or_create_shared_settings(db, current_user.tenant_id)
    await db.commit()
    await db.refresh(settings)
    return SharedSettingsResponse(
        tenant_id=settings.tenant_id,
        settings_json=settings.settings_json or {},
        updated_at=settings.updated_at,
    )


@router.put("/shared", response_model=SharedSettingsResponse)
async def update_shared_settings(
    payload: SharedSettingsPatch,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Merge-patch: merges top-level keys from payload.settings into shared settings_json."""
    settings = await _get_or_create_shared_settings(db, current_user.tenant_id)
    current = dict(settings.settings_json or {})
    current.update(payload.settings)
    settings.settings_json = current
    settings.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(settings)
    return SharedSettingsResponse(
        tenant_id=settings.tenant_id,
        settings_json=settings.settings_json or {},
        updated_at=settings.updated_at,
    )
