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


class PortalDocumentCollectionDraftInfoResponse(BaseModel):
    available: bool = False
    status: str = "not_started"
    current_step: Optional[str] = None
    updated_at: Optional[datetime] = None
    submitted_at: Optional[datetime] = None


class PortalActFlowResponse(BaseModel):
    status: str
    label: str
    provider: Optional[str] = None
    signing_url: Optional[str] = None
    provider_reference: Optional[str] = None
    request_id: Optional[str] = None
    act_document_id: Optional[str] = None
    signed_document_id: Optional[str] = None
    countersigned_document_id: Optional[str] = None
    signed_at: Optional[datetime] = None
    countersigned_at: Optional[datetime] = None


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
    inspection_scheduling_enabled: bool = False
    requested_amount: Optional[float] = None
    liquidated_amount: Optional[float] = None
    estimated_damage_amount: Optional[float] = None
    act_sent_at: Optional[datetime] = None
    act_signed_at: Optional[datetime] = None
    contraente_name: Optional[str] = None
    iban_value_masked: Optional[str] = None
    iban_required_for_progress: bool = True
    document_collection_draft: PortalDocumentCollectionDraftInfoResponse = Field(default_factory=PortalDocumentCollectionDraftInfoResponse)
    additional_document_requests: list[str] = Field(default_factory=list)
    act_flow: Optional[PortalActFlowResponse] = None


class PortalAccessibleClaimResponse(BaseModel):
    claim_id: str
    tenant_id: str
    external_ref: Optional[str] = None
    numero_sinistro: Optional[str] = None
    compagnia: Optional[str] = None
    nome_assicurato: Optional[str] = None
    data_sinistro: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    macro_state: PortalMacroStateResponse
    has_pending_actions: bool = False
    requested_amount: Optional[float] = None
    liquidated_amount: Optional[float] = None
    estimated_damage_amount: Optional[float] = None


class PortalTimelineEventResponse(BaseModel):
    id: str
    event_type: str
    event_time: datetime
    label: str
    description: Optional[str] = None
    source: str


class PortalInspectionLocationUpdateRequest(BaseModel):
    address_line: Optional[str] = None
    municipality: Optional[str] = None
    province: Optional[str] = None
    region: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class PortalInspectionSelectedSlotInput(BaseModel):
    date: str
    start_time: str
    end_time: str
    label: Optional[str] = None


class PortalInspectionPreferencesUpdateRequest(BaseModel):
    selected_slots: list[PortalInspectionSelectedSlotInput] = Field(default_factory=list)
    notes: Optional[str] = None
    requested_duration_minutes: Optional[int] = Field(default=None, ge=60, le=240)


class PortalInspectionLocationResponse(BaseModel):
    address_line: Optional[str] = None
    municipality: Optional[str] = None
    province: Optional[str] = None
    region: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    confirmed_at: Optional[datetime] = None


class PortalInspectionSelectedSlotResponse(BaseModel):
    id: str
    date: str
    start_at: datetime
    end_at: datetime
    label: str


class PortalInspectionAvailabilitySlotResponse(BaseModel):
    id: str
    date: str
    start_at: datetime
    end_at: datetime
    label: str
    available_cat_count: int
    candidate_user_ids: list[str]


class PortalInspectionAvailabilityDayResponse(BaseModel):
    date: str
    weekday_label: str
    is_available: bool
    slot_count: int
    slots: list[PortalInspectionAvailabilitySlotResponse] = Field(default_factory=list)


class PortalInspectionCandidateResponse(BaseModel):
    user_id: str
    full_name: str
    email: Optional[str] = None
    phone_number: Optional[str] = None
    job_title: Optional[str] = None
    comune: Optional[str] = None
    provincia: Optional[str] = None
    regione: Optional[str] = None
    distance_km: Optional[float] = None
    is_primary_zone: bool = False


class PortalInspectionSchedulingOverviewResponse(BaseModel):
    enabled: bool
    status: str
    workflow_stage: Optional[str] = None
    instructions: str
    pending_confirmation_message: Optional[str] = None
    address_confirmed: bool
    location: PortalInspectionLocationResponse
    selected_slots: list[PortalInspectionSelectedSlotResponse] = Field(default_factory=list)
    availability_days: list[PortalInspectionAvailabilityDayResponse] = Field(default_factory=list)
    candidate_cats: list[PortalInspectionCandidateResponse] = Field(default_factory=list)
    route_review_deadline: Optional[datetime] = None
    route_proposal_event_id: Optional[str] = None


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


class PortalUploadedDocumentResponse(BaseModel):
    document_id: str
    file_name: str
    status: str
    storage_path: str
    uploaded_at: datetime


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


class PortalDocumentCollectionDraftUpdateRequest(BaseModel):
    draft_json: dict = Field(default_factory=dict)


class PortalDocumentCollectionDraftResponse(BaseModel):
    status: str
    draft_json: dict = Field(default_factory=dict)
    updated_at: Optional[datetime] = None


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


class PortalAdditionalDocumentSubmissionCreate(BaseModel):
    note: Optional[str] = None
    document_ids: list[str] = Field(default_factory=list)
    requested_items: list[str] = Field(default_factory=list)


class PortalAdditionalDocumentSubmissionResponse(BaseModel):
    status: str
    submitted_at: datetime
    document_count: int


class PortalAdditionalDocumentRequestsUpdate(BaseModel):
    items: list[str] = Field(default_factory=list)


class PortalActFlowUpdateRequest(BaseModel):
    provider: str
    signing_url: Optional[str] = None
    provider_reference: Optional[str] = None
    request_id: Optional[str] = None
    act_document_id: Optional[str] = None
    status: str = "pending_external_signature"
    signed_document_id: Optional[str] = None
    countersigned_document_id: Optional[str] = None
    signed_at: Optional[datetime] = None
    countersigned_at: Optional[datetime] = None


class PortalSignatureProviderWebhookRequest(BaseModel):
    claim_id: Optional[str] = None
    request_id: Optional[str] = None
    provider_reference: Optional[str] = None
    status: str
    signing_url: Optional[str] = None
    act_document_id: Optional[str] = None
    signed_document_id: Optional[str] = None
    countersigned_document_id: Optional[str] = None
    signed_at: Optional[datetime] = None
    countersigned_at: Optional[datetime] = None
