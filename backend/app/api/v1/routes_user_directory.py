"""
User directory routes
- Tenant user list with presence info
- Presence update (last_seen_at + work_location stored in user_settings JSON)
- My profile GET/PUT
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.models.user_settings import UserSettings
from app.schemas.user_settings import (
    PresenceUpdate,
    UserDirectoryEntry,
    UserDirectoryListResponse,
    UserProfileUpdate,
)

router = APIRouter()


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


def _presence_from_settings(settings_json: dict | None) -> tuple[datetime | None, str | None]:
    """Extract last_seen_at and work_location from settings_json presence block."""
    if not settings_json:
        return None, None
    presence = settings_json.get("presence", {})
    last_seen_raw = presence.get("last_seen")
    location = presence.get("location")
    last_seen = None
    if last_seen_raw:
        try:
            last_seen = datetime.fromisoformat(last_seen_raw)
        except (ValueError, TypeError):
            pass
    return last_seen, location


def _build_directory_entry(user: User, settings_json: dict | None) -> UserDirectoryEntry:
    last_seen, location = _presence_from_settings(settings_json)
    return UserDirectoryEntry(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        first_name=user.first_name,
        last_name=user.last_name,
        job_title=user.job_title,
        avatar_type=user.avatar_type,
        avatar_photo_base64=user.avatar_photo_base64,
        generated_avatar_color=user.generated_avatar_color,
        generated_avatar_icon=user.generated_avatar_icon,
        avatar_gif_url=user.avatar_gif_url,
        contract_type=user.contract_type,
        is_active=user.is_active,
        last_seen_at=last_seen,
        work_location=location,
    )


@router.get("/", response_model=UserDirectoryListResponse)
async def list_users(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """List all active users in the same tenant with their presence info."""
    users_result = await db.execute(
        select(User).where(
            User.tenant_id == current_user.tenant_id,
            User.is_active == True,
        ).order_by(User.full_name.asc())
    )
    users = users_result.scalars().all()

    # Batch fetch all user settings for this tenant
    user_ids = [u.id for u in users]
    settings_result = await db.execute(
        select(UserSettings).where(UserSettings.user_id.in_(user_ids))
    )
    settings_map: dict[str, dict] = {
        s.user_id: (s.settings_json or {}) for s in settings_result.scalars().all()
    }

    items = [_build_directory_entry(u, settings_map.get(u.id)) for u in users]
    return UserDirectoryListResponse(items=items, total=len(items))


@router.get("/me", response_model=UserDirectoryEntry)
async def get_my_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    settings = await _get_or_create_user_settings(db, current_user)
    await db.commit()
    return _build_directory_entry(current_user, settings.settings_json)


@router.put("/me", response_model=UserDirectoryEntry)
async def update_my_profile(
    payload: UserProfileUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(current_user, field, value)
    settings = await _get_or_create_user_settings(db, current_user)
    await db.commit()
    await db.refresh(current_user)
    return _build_directory_entry(current_user, settings.settings_json)


@router.put("/me/presence", response_model=UserDirectoryEntry)
async def update_my_presence(
    payload: PresenceUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Update last_seen_at and work_location stored inside user_settings JSON."""
    settings = await _get_or_create_user_settings(db, current_user)
    current_json = dict(settings.settings_json or {})
    current_json["presence"] = {
        "last_seen": datetime.now(timezone.utc).isoformat(),
        "location": payload.location,
    }
    settings.settings_json = current_json
    settings.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(settings)
    return _build_directory_entry(current_user, settings.settings_json)
