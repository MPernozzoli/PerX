"""
Device token registration for APNs / VoIP push notifications.
Used by the PerX Lite iOS app.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.device_token import DeviceToken
from app.models.user import User


router = APIRouter()


class DeviceTokenRegisterRequest(BaseModel):
    token: str = Field(..., min_length=8)
    token_type: str = Field(..., pattern="^(apns|voip)$")
    platform: str = "ios"
    bundle_id: Optional[str] = None
    environment: str = Field("production", pattern="^(production|sandbox)$")
    app: Optional[str] = None


class DeviceTokenResponse(BaseModel):
    id: str
    token_type: str
    platform: str
    environment: str
    app: Optional[str] = None
    bundle_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


@router.post("/register", response_model=DeviceTokenResponse)
async def register_device_token(
    payload: DeviceTokenRegisterRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    # Upsert by (token, token_type)
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == payload.token,
            DeviceToken.token_type == payload.token_type,
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        existing.tenant_id = current_user.tenant_id
        existing.user_id = current_user.id
        existing.platform = payload.platform
        existing.bundle_id = payload.bundle_id
        existing.environment = payload.environment
        existing.app = payload.app
        existing.last_used_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(existing)
        return DeviceTokenResponse.model_validate(existing)

    device = DeviceToken(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        token=payload.token,
        token_type=payload.token_type,
        platform=payload.platform,
        bundle_id=payload.bundle_id,
        environment=payload.environment,
        app=payload.app,
        last_used_at=datetime.now(timezone.utc),
    )
    db.add(device)
    await db.commit()
    await db.refresh(device)
    return DeviceTokenResponse.model_validate(device)


@router.delete("/{token}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device_token(
    token: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token,
            DeviceToken.user_id == current_user.id,
        )
    )
    devices = result.scalars().all()
    if not devices:
        raise HTTPException(status_code=404, detail="Device token not found")
    for d in devices:
        await db.delete(d)
    await db.commit()
