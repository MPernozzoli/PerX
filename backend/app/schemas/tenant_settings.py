"""
Tenant settings schemas
"""
from pydantic import BaseModel, EmailStr, Field


class TenantCATPlannerSettings(BaseModel):
    route_generation_hour: int = 9
    route_review_window_minutes: int = 60
    availability_slot_minutes: int = 120
    availability_tolerance_percent: int = 50
    max_outside_zone_kilometers: int = 50


class TenantCATPOI(BaseModel):
    id: str
    display_name: str
    email: str
    latitude: float
    longitude: float
    comune: str = ""
    provincia: str = ""
    regione: str = ""
    assigned_municipalities: list[str] = Field(default_factory=list)
    note: str = ""


class TenantCATMunicipality(BaseModel):
    id: str
    comune: str
    provincia: str
    regione: str
    latitude: float
    longitude: float
    assigned_cat_emails: list[str] = Field(default_factory=list)
    priority: int = 1


class TenantCATSettingsPayload(BaseModel):
    enabled: bool = True
    planner: TenantCATPlannerSettings = Field(default_factory=TenantCATPlannerSettings)
    technicians: list[TenantCATPOI] = Field(default_factory=list)
    municipalities: list[TenantCATMunicipality] = Field(default_factory=list)


class TenantInspectionProviderSettingsPayload(BaseModel):
    map_provider: str = "google_maps"
    maps_api_key: str = ""
    routing_provider: str = "google_routes"
    routing_api_key: str = ""
    routing_enabled: bool = False
    routing_cache_ttl_days: int = 14
    geocoding_provider: str = "google_geocoding"
    geocoding_api_key: str = ""
    messaging_provider: str = "twilio"
    messaging_api_key: str = ""


class TenantAISettingsPayload(BaseModel):
    openai_api_key: str = ""
    openai_model: str = "gpt-4o"
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-opus-4-7"


class TenantAIKeysResponse(BaseModel):
    openai_api_key: str
    openai_model: str
    anthropic_api_key: str
    anthropic_model: str


class TenantMailSettingsPayload(BaseModel):
    tenant_name: str = Field(..., min_length=1)
    tenant_slug: str = Field(..., min_length=1)
    portal_domains: list[str] = Field(default_factory=list)
    internal_domains: list[str] = Field(default_factory=list)
    internal_emails: list[EmailStr] = Field(default_factory=list)
    system_emails: list[EmailStr] = Field(default_factory=list)
    secretariat_emails: list[EmailStr] = Field(default_factory=list)
    claim_garanzie: list[str] = Field(default_factory=lambda: ["Fenomeno Elettrico"])
    default_claim_garanzia: str = "Fenomeno Elettrico"
    cat_settings: TenantCATSettingsPayload = Field(default_factory=TenantCATSettingsPayload)
    provider_settings: TenantInspectionProviderSettingsPayload | None = None
    ai_settings: TenantAISettingsPayload | None = None


class TenantSettingsResponse(BaseModel):
    tenant_id: str
    tenant_name: str
    tenant_slug: str
    portal_domains: list[str]
    internal_domains: list[str]
    internal_emails: list[EmailStr]
    system_emails: list[EmailStr]
    secretariat_emails: list[EmailStr]
    claim_garanzie: list[str]
    default_claim_garanzia: str
    cat_settings: TenantCATSettingsPayload
    provider_settings: TenantInspectionProviderSettingsPayload | None = None
    ai_settings: TenantAISettingsPayload | None = None


class TenantUserResponse(BaseModel):
    id: str
    tenant_id: str
    personal_email: EmailStr
    professional_email: EmailStr | None = None
    email_aliases: list[EmailStr] = Field(default_factory=list)
    first_name: str = ""
    last_name: str = ""
    full_name: str
    job_title: str | None = None
    phone_number: str | None = None
    contract_type: str | None = None
    roles: list[str] = Field(default_factory=list)
    is_active: bool
    invite_status: str | None = None
    invited_at: str | None = None
    last_login_at: str | None = None


class TenantUserCreateRequest(BaseModel):
    personal_email: EmailStr
    first_name: str = Field(..., min_length=1)
    last_name: str = Field(..., min_length=1)
    job_title: str | None = None
    phone_number: str | None = None
    contract_type: str | None = None
    roles: list[str] = Field(default_factory=list)
    send_invite: bool = True


class TenantUserUpdateRequest(BaseModel):
    first_name: str = Field(..., min_length=1)
    last_name: str = Field(..., min_length=1)
    job_title: str | None = None
    phone_number: str | None = None
    contract_type: str | None = None
    roles: list[str] = Field(default_factory=list)
    is_active: bool = True
    professional_email: EmailStr | None = None


class TenantUserInviteResponse(BaseModel):
    user: TenantUserResponse
    invite_status: str
    invite_error: str | None = None
