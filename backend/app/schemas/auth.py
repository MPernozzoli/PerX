"""
Authentication schemas
"""
from pydantic import BaseModel, EmailStr
from typing import Optional


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: Optional[str] = None


class LoginRequest(BaseModel):
    username: str  # email
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class UserResponse(BaseModel):
    id: str
    email: str
    personal_email: Optional[str] = None
    professional_email: Optional[str] = None
    email_aliases: list[str] = []
    full_name: str
    first_name: str = ""
    last_name: str = ""
    job_title: Optional[str] = None
    phone_number: Optional[str] = None
    birth_date: Optional[str] = None
    birthday_visibility: str = "everyone"
    notify_birthday: bool = True
    contract_type: Optional[str] = None
    roles: list[str] = []
    avatar_type: str = "generated"
    avatar_photo_base64: Optional[str] = None
    generated_avatar_color: Optional[str] = None
    generated_avatar_icon: Optional[str] = None
    avatar_gif_url: Optional[str] = None
    enable_badges: bool = False
    send_read_receipts: bool = True
    email_signature_html: Optional[str] = None
    email_signature_text: Optional[str] = None
    is_active: bool
    tenant_id: str
    is_platform_admin: bool
    
    class Config:
        from_attributes = True
