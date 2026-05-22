"""
Pydantic schemas for user_settings and shared_settings
"""
from __future__ import annotations
from datetime import datetime
from typing import Any, Dict, Optional, List
from pydantic import BaseModel


class UserSettingsResponse(BaseModel):
    user_id: str
    tenant_id: str
    settings_json: Dict[str, Any]
    updated_at: datetime

    model_config = {"from_attributes": True}


class UserSettingsPatch(BaseModel):
    """Partial update — keys provided will be merged into existing settings_json."""
    settings: Dict[str, Any]


class SharedSettingsResponse(BaseModel):
    tenant_id: str
    settings_json: Dict[str, Any]
    updated_at: datetime

    model_config = {"from_attributes": True}


class SharedSettingsPatch(BaseModel):
    settings: Dict[str, Any]


# ------------------------------------------------------------------
# User directory schemas
# ------------------------------------------------------------------

class PresenceUpdate(BaseModel):
    location: str  # "office" | "remote" | "not_working"


class UserDirectoryEntry(BaseModel):
    id: str
    email: str
    full_name: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    job_title: Optional[str] = None
    avatar_type: Optional[str] = None
    avatar_photo_base64: Optional[str] = None
    generated_avatar_color: Optional[str] = None
    generated_avatar_icon: Optional[str] = None
    avatar_gif_url: Optional[str] = None
    contract_type: Optional[str] = None
    is_active: bool
    last_seen_at: Optional[datetime] = None
    work_location: Optional[str] = None

    model_config = {"from_attributes": True}


class UserDirectoryListResponse(BaseModel):
    items: List[UserDirectoryEntry]
    total: int


class UserProfileUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    full_name: Optional[str] = None
    job_title: Optional[str] = None
    avatar_type: Optional[str] = None
    avatar_photo_base64: Optional[str] = None
    generated_avatar_color: Optional[str] = None
    generated_avatar_icon: Optional[str] = None
    avatar_gif_url: Optional[str] = None
    contract_type: Optional[str] = None
