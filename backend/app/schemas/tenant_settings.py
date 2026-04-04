"""
Tenant settings schemas
"""
from pydantic import BaseModel, EmailStr, Field


class TenantMailSettingsPayload(BaseModel):
    tenant_name: str = Field(..., min_length=1)
    tenant_slug: str = Field(..., min_length=1)
    internal_domains: list[str] = Field(default_factory=list)
    internal_emails: list[EmailStr] = Field(default_factory=list)
    system_emails: list[EmailStr] = Field(default_factory=list)
    secretariat_emails: list[EmailStr] = Field(default_factory=list)
    claim_garanzie: list[str] = Field(default_factory=lambda: ["Fenomeno Elettrico"])
    default_claim_garanzia: str = "Fenomeno Elettrico"


class TenantSettingsResponse(BaseModel):
    tenant_id: str
    tenant_name: str
    tenant_slug: str
    internal_domains: list[str]
    internal_emails: list[EmailStr]
    system_emails: list[EmailStr]
    secretariat_emails: list[EmailStr]
    claim_garanzie: list[str]
    default_claim_garanzia: str
