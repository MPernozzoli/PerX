"""
User profile schemas
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class UserProfileResponse(BaseModel):
    id: str
    email: str
    personal_email: Optional[str] = None
    professional_email: Optional[str] = None
    email_aliases: list[str] = Field(default_factory=list)
    full_name: str
    first_name: str = ""
    last_name: str = ""
    job_title: Optional[str] = None
    phone_number: Optional[str] = None
    birth_date: Optional[datetime] = None
    birthday_visibility: str = "everyone"
    notify_birthday: bool = True
    contract_type: Optional[str] = None
    roles: list[str] = Field(default_factory=list)
    extension_number: Optional[str] = None
    extension_enabled: bool = False
    extension_assigned_at: Optional[datetime] = None
    extension_display_name: Optional[str] = None
    availability_status: str = "available"
    communication_status: str = "idle"
    avatar_type: str = "generated"
    avatar_photo_base64: Optional[str] = None
    avatar_asset_url: Optional[str] = None
    generated_avatar_color: Optional[str] = None
    generated_avatar_icon: Optional[str] = None
    avatar_gif_url: Optional[str] = None
    signature_image_url: Optional[str] = None
    enable_badges: bool = False
    send_read_receipts: bool = True
    email_signature_html: Optional[str] = None
    email_signature_text: Optional[str] = None
    tenant_id: str
    is_active: bool
    is_platform_admin: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class UserProfileUpdateRequest(BaseModel):
    first_name: str = ""
    last_name: str = ""
    job_title: Optional[str] = None
    phone_number: Optional[str] = None
    birth_date: Optional[datetime] = None
    birthday_visibility: str = "everyone"
    notify_birthday: bool = True
    contract_type: Optional[str] = None
    roles: list[str] = Field(default_factory=list)
    extension_number: Optional[str] = None
    extension_enabled: Optional[bool] = None
    extension_display_name: Optional[str] = None
    availability_status: str = "available"
    communication_status: str = "idle"
    avatar_type: str = "generated"
    avatar_photo_base64: Optional[str] = None
    generated_avatar_color: Optional[str] = None
    generated_avatar_icon: Optional[str] = None
    avatar_gif_url: Optional[str] = None
    enable_badges: bool = False
    send_read_receipts: bool = True
    email_signature_html: Optional[str] = None
    email_signature_text: Optional[str] = None
    professional_email: Optional[str] = None


class UserProfileAssetResponse(BaseModel):
    asset_type: str
    file_name: str
    mime_type: Optional[str] = None
    size_bytes: int
    asset_url: str
    updated_at: Optional[datetime] = None
