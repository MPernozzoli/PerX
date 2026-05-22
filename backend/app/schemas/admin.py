"""
Schemas for platform-admin APIs
"""
from pydantic import BaseModel, Field
from typing import Any, Literal


class TenantResponse(BaseModel):
    id: str
    name: str
    slug: str

    class Config:
        from_attributes = True


class TenantUpsert(BaseModel):
    name: str = Field(..., min_length=1)
    slug: str = Field(..., min_length=1)
    settings_json: dict[str, Any] | None = None


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


DomainRouteApp = Literal["catdispatcher", "perx_admin", "insured_portal"]


class DomainRouteResponse(BaseModel):
    id: str
    hostname: str
    app: DomainRouteApp
    tenant_id: str | None = None
    tenant_name: str | None = None
    destination_url: str | None = None
    is_active: bool
    notes: str | None = None
    metadata_json: dict[str, Any] | None = None


class DomainRouteUpsert(BaseModel):
    hostname: str
    app: DomainRouteApp
    tenant_id: str | None = None
    destination_url: str | None = None
    is_active: bool = True
    notes: str | None = None
    metadata_json: dict[str, Any] | None = None
