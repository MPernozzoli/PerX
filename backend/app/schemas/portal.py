"""
Schemas for the insured portal API.
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class PortalAccessInviteRequest(BaseModel):
    full_name: str
    email: str
    phone_number: Optional[str] = None
    tax_code: Optional[str] = None
    role: str = "insured"
    is_primary: bool = True
    preferred_channel: str = "email"
    metadata_json: Optional[dict] = None


class PortalAccessInviteResponse(BaseModel):
    portal_access_id: str
    challenge_id: str
    masked_destination: Optional[str] = None
    magic_link_url: str
    expires_at: datetime


class PortalAuthStartRequest(BaseModel):
    claim_reference: Optional[str] = None
    tax_code: Optional[str] = None
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    channel: str = "email"


class PortalAuthStartResponse(BaseModel):
    status: str
    challenge_id: Optional[str] = None
    delivery_channel: Optional[str] = None
    masked_destination: Optional[str] = None
    expires_at: Optional[datetime] = None
    preview_magic_link_url: Optional[str] = None


class PortalAuthExchangeRequest(BaseModel):
    token: str


class PortalAuthExchangeResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    claim_id: str
    portal_access_id: str


class PortalMacroStateResponse(BaseModel):
    code: str
    label: str
    description: str
    needs_action: bool
    internal_state: Optional[str] = None


class PortalRequirementResponse(BaseModel):
    key: str
    label: str
    status: str
    description: str


class PortalAppointmentResponse(BaseModel):
    id: str
    title: str
    starts_at: datetime
    ends_at: datetime
    location: Optional[str] = None
    status: str


class PortalExpertContactResponse(BaseModel):
    user_id: Optional[str] = None
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone_number: Optional[str] = None
    job_title: Optional[str] = None
    is_available_now: bool = False
    is_online: bool = False
    availability_note: Optional[str] = None


class PortalClaimSummaryResponse(BaseModel):
    claim_id: str
    tenant_id: str
    external_ref: Optional[str] = None
    numero_sinistro: Optional[str] = None
    compagnia: Optional[str] = None
    nome_assicurato: Optional[str] = None
    data_sinistro: Optional[datetime] = None
    macro_state: PortalMacroStateResponse
    expert: PortalExpertContactResponse
    requirements: list[PortalRequirementResponse]
    upcoming_appointment: Optional[PortalAppointmentResponse] = None
    chat_enabled: bool = True
    document_upload_enabled: bool = True
    act_signature_enabled: bool = True


class PortalTimelineEventResponse(BaseModel):
    id: str
    event_type: str
    event_time: datetime
    label: str
    description: Optional[str] = None
    source: str


class PortalDocumentResponse(BaseModel):
    id: str
    file_name: str
    category: Optional[str] = None
    status: str
    uploaded_at: datetime


class PortalUploadIntentCreate(BaseModel):
    file_name: str
    mime_type: Optional[str] = None
    size_bytes: int = Field(default=0, ge=0)
    category: Optional[str] = None


class PortalUploadIntentResponse(BaseModel):
    document_id: str
    upload_mode: str
    upload_url: Optional[str] = None
    storage_path: str
    expires_in: int


class PortalConversationMessageCreate(BaseModel):
    body_text: str = Field(min_length=1, max_length=4000)


class PortalConversationMessageResponse(BaseModel):
    id: str
    author_type: str
    body_text: str
    created_at: datetime


class PortalConversationMessageListResponse(BaseModel):
    items: list[PortalConversationMessageResponse]
    total: int


class PortalDocumentCollectionItemInput(BaseModel):
    name: str
    brand: Optional[str] = None
    model: Optional[str] = None
    purchase_year: Optional[int] = None
    quantity: int = Field(default=1, ge=1)


class PortalDocumentCollectionSubmissionCreate(BaseModel):
    items: list[PortalDocumentCollectionItemInput] = Field(default_factory=list)
    notes: Optional[str] = None
    location_latitude: Optional[float] = None
    location_longitude: Optional[float] = None
    photos_count: int = Field(default=0, ge=0)
    metadata_json: Optional[dict] = None


class PortalDocumentCollectionSubmissionResponse(BaseModel):
    id: str
    status: str
    submitted_at: datetime


class PortalBankAccountSubmissionCreate(BaseModel):
    iban: str
    account_holder: Optional[str] = None


class PortalIbanValidationResponse(BaseModel):
    is_valid: bool
    normalized_iban: str
    country_code: Optional[str] = None
    check_digits: Optional[str] = None
    cin: Optional[str] = None
    abi: Optional[str] = None
    cab: Optional[str] = None
    account_number: Optional[str] = None
    reason: Optional[str] = None


class PortalBankAccountSubmissionResponse(BaseModel):
    id: str
    status: str
    submitted_at: datetime
    validation: PortalIbanValidationResponse


class PortalSignatureRequestCreate(BaseModel):
    document_id: str
    signature_method: str = "otp"


class PortalSignatureRequestResponse(BaseModel):
    id: str
    status: str
    challenge_id: Optional[str] = None
    expires_at: Optional[datetime] = None
    preview_token: Optional[str] = None


class PortalSignatureConfirmRequest(BaseModel):
    token: str


class PortalSignatureConfirmResponse(BaseModel):
    id: str
    status: str
    signed_at: Optional[datetime] = None
