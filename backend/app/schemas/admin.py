"""
Schemas for platform-admin APIs
"""
from pydantic import BaseModel


class TenantResponse(BaseModel):
    id: str
    name: str
    slug: str

    class Config:
        from_attributes = True


class AdminUserResponse(BaseModel):
    id: str
    tenant_id: str
    email: str
    personal_email: str | None = None
    professional_email: str | None = None
    full_name: str
    is_active: bool
    is_platform_admin: bool

    class Config:
        from_attributes = True
