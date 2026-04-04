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


class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str
    is_active: bool
    tenant_id: str
    is_platform_admin: bool
    
    class Config:
        from_attributes = True
