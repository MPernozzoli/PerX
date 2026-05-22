"""
Schemas for unified login user invitations.
"""
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class InvitationCreate(BaseModel):
    personal_email: EmailStr
    full_name: str = Field(min_length=1)
    tenant_id: str
    roles: list[str] = []
    expires_in_hours: int = Field(default=72, ge=1, le=24 * 30)
    metadata_json: dict | None = None


class InvitationCreateResponse(BaseModel):
    id: str
    user_id: str
    tenant_id: str
    personal_email: str
    status: str
    expires_at: datetime
    invite_url: str


class InvitationPublicResponse(BaseModel):
    id: str
    tenant_id: str
    personal_email: str
    full_name: str
    status: str
    expires_at: datetime


class InvitationAccept(BaseModel):
    idp_subject: str = Field(min_length=1)
    professional_email: EmailStr | None = None


class InvitationAcceptResponse(BaseModel):
    user_id: str
    tenant_id: str
    personal_email: str
    professional_email: str | None = None
    status: str
