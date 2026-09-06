"""
Schemas for platform-admin APIs
"""
from datetime import datetime
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


DomainRouteApp = Literal["bignami", "catdispatcher", "insight_studio", "perx_admin", "randa", "insured_portal"]


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


ErrorSeverity = Literal["warning", "error", "critical"]


class PlatformErrorResponse(BaseModel):
    id: str
    tenant_id: str | None = None
    tenant_name: str | None = None
    source: str
    severity: ErrorSeverity
    message: str
    stack_trace: str | None = None
    path: str | None = None
    method: str | None = None
    status_code: int | None = None
    context_json: dict[str, Any] | None = None
    resolved: bool
    resolved_at: datetime | None = None
    resolved_by_user_id: str | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class PlatformErrorResolvePayload(BaseModel):
    resolved: bool = True
