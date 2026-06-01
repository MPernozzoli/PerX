"""
Schemi per la sezione "Impostazioni e privacy" del portale assicurato.
Tutti gli endpoint vivono sotto /api/v1/portal/me/*.
"""
from __future__ import annotations

from datetime import date, datetime, time
from typing import List, Literal, Optional

from pydantic import BaseModel, EmailStr, Field


# ----------------------------------------------------------------------
# Profile
# ----------------------------------------------------------------------

class PortalMeProfileResponse(BaseModel):
    """Vista read-only di cosa lo studio sa dell'assicurato (GDPR art. 15).
    L'indirizzo NON è qui perché è quello di polizza, non editabile."""
    actor_id: Optional[str] = None
    display_name: str
    actor_type: Optional[str] = None
    codice_fiscale_masked: Optional[str] = None
    partita_iva_masked: Optional[str] = None
    data_nascita: Optional[date] = None
    luogo_nascita: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    pec: Optional[str] = None


class PortalMeProfileUpdate(BaseModel):
    """Solo email e telefono sono modificabili dall'assicurato.
    Tutto il resto (CF, indirizzo, nome) richiede intervento dello studio."""
    email: Optional[EmailStr] = None
    phone: Optional[str] = None


# ----------------------------------------------------------------------
# Privacy policy + consents
# ----------------------------------------------------------------------

class PortalMePolicyResponse(BaseModel):
    id: str
    version: int
    title: Optional[str] = None
    summary: Optional[str] = None
    content_md: str
    effective_from: datetime


class PortalMeConsentResponse(BaseModel):
    id: str
    policy_id: str
    policy_version: int
    accepted_at: datetime
    consent_type: str

    model_config = {"from_attributes": True}


class PortalMeConsentAcceptRequest(BaseModel):
    policy_id: str
    consent_type: str = "privacy"


# ----------------------------------------------------------------------
# Notifications
# ----------------------------------------------------------------------

NotificationChannel = Literal["email", "whatsapp", "sms", "push"]


class PortalMeNotificationPrefs(BaseModel):
    channel_push: bool = False
    channel_email: bool = True
    channel_whatsapp: bool = False
    channel_sms: bool = False
    preferred_channel: NotificationChannel = "email"
    allow_phone_calls: bool = True
    call_window_start: Optional[time] = None
    call_window_end: Optional[time] = None
    quiet_hours_start: Optional[time] = None
    quiet_hours_end: Optional[time] = None
    documents_via_email: bool = False


class PortalMeNotificationPrefsResponse(PortalMeNotificationPrefs):
    updated_at: Optional[datetime] = None


# ----------------------------------------------------------------------
# Deletion request
# ----------------------------------------------------------------------

class PortalMeDeletionRequestCreate(BaseModel):
    reason: Optional[str] = Field(default=None, max_length=2000)


class PortalMeDeletionRequestResponse(BaseModel):
    id: str
    requested_at: datetime
    eligible_from: datetime
    status: str
    reason: Optional[str] = None
    processed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ----------------------------------------------------------------------
# Sessions
# ----------------------------------------------------------------------

class PortalMeSessionResponse(BaseModel):
    id: str
    device_label: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    created_at: datetime
    last_seen_at: datetime
    is_current: bool = False

    model_config = {"from_attributes": True}


# ----------------------------------------------------------------------
# Export (GDPR art. 15/20) — self-service from portal
# ----------------------------------------------------------------------

class PortalMeExportOtpRequest(BaseModel):
    """Step 1 dello step-up: l'assicurato richiede l'OTP per autorizzare
    l'export. L'OTP viene inviato sul canale verificato (di solito email)."""
    pass


class PortalMeExportRequest(BaseModel):
    """Step 2: l'assicurato conferma con l'OTP ricevuto."""
    otp_code: str = Field(..., min_length=4, max_length=10)
