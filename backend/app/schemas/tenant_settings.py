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
    geocoding_provider: str = "google_geocoding"
    geocoding_api_key: str = ""
    messaging_provider: str = "twilio"
    messaging_api_key: str = ""


class TenantMailSettingsPayload(BaseModel):
    tenant_name: str = Field(..., min_length=1)
    tenant_slug: str = Field(..., min_length=1)
    internal_domains: list[str] = Field(default_factory=list)
    internal_emails: list[EmailStr] = Field(default_factory=list)
    system_emails: list[EmailStr] = Field(default_factory=list)
    secretariat_emails: list[EmailStr] = Field(default_factory=list)
    claim_garanzie: list[str] = Field(default_factory=lambda: ["Fenomeno Elettrico"])
    default_claim_garanzia: str = "Fenomeno Elettrico"
    cat_settings: TenantCATSettingsPayload = Field(default_factory=TenantCATSettingsPayload)
    provider_settings: TenantInspectionProviderSettingsPayload | None = None


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
    cat_settings: TenantCATSettingsPayload
    provider_settings: TenantInspectionProviderSettingsPayload | None = None
