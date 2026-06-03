"""
Communication schemas for the unified Telefono module.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class AvailabilityStatus(str, Enum):
    available = "available"
    busy = "busy"
    away = "away"
    offline = "offline"
    do_not_disturb = "do_not_disturb"


class CommunicationStatus(str, Enum):
    idle = "idle"
    ringing = "ringing"
    in_call = "in_call"
    on_hold = "on_hold"
    unavailable = "unavailable"


class CommunicationDestinationType(str, Enum):
    external_phone = "external_phone"
    internal_user = "internal_user"
    internal_extension = "internal_extension"
    internal_team = "internal_team"
    queue = "queue"
    livekit_room = "livekit_room"
    external_guest_link = "external_guest_link"
    cross_tenant_perx = "cross_tenant_perx"


class CommunicationTransport(str, Enum):
    telecom_provider = "telecom_provider"
    livekit = "livekit"
    routing_engine = "routing_engine"


class CommunicationContext(BaseModel):
    tenant_id: Optional[str] = None
    claim_id: Optional[str] = None
    claim_reference: Optional[str] = None
    scheduled_communication_id: Optional[str] = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class CommunicationDestination(BaseModel):
    destination_type: CommunicationDestinationType
    transport: CommunicationTransport
    target_id: Optional[str] = None
    display_name: str
    tenant_id: str
    suggested_caller_id: Optional[str] = None
    context_claim_id: Optional[str] = None
    raw_value: str


class CommunicationResolutionResponse(BaseModel):
    selected: Optional[CommunicationDestination] = None
    candidates: list[CommunicationDestination] = Field(default_factory=list)
    is_ambiguous: bool = False


class CommunicationResolveRequest(BaseModel):
    destination: str
    context: CommunicationContext = Field(default_factory=CommunicationContext)


class CommunicationStartRequest(BaseModel):
    destination: CommunicationDestination
    context: CommunicationContext = Field(default_factory=CommunicationContext)


class CommunicationStartResponse(BaseModel):
    session_id: str
    call_id: str
    state: str
    destination: CommunicationDestination
    created_at: datetime
    service_contract: str = "startCommunication(destination, context)"
    livekit_token: Optional["CommunicationLiveKitTokenResponse"] = None


class CommunicationClaimContext(BaseModel):
    claim_id: str
    claim_reference: Optional[str] = None
    claim_number: Optional[str] = None
    claim_status: Optional[str] = None
    insured_name: Optional[str] = None


class CommunicationCallerContext(BaseModel):
    display_name: str
    source: str
    contact_type: Optional[str] = None
    phone_number: Optional[str] = None
    claim_context: Optional[CommunicationClaimContext] = None


class CommunicationNotificationActionType(str, Enum):
    answer = "answer"
    answer_and_open_claim = "answer_and_open_claim"
    open_claim_only = "open_claim_only"
    send_to_voicemail_ai_triage = "send_to_voicemail_ai_triage"


class CommunicationNotificationAction(BaseModel):
    action_type: CommunicationNotificationActionType
    title: str
    emphasized: bool = False
    requires_claim: bool = False


class CommunicationLiveKitTokenResponse(BaseModel):
    token: str
    livekit_url: str
    room_name: str
    identity: str
    expires_at: datetime
    can_publish: bool
    can_subscribe: bool
    session_id: str
    call_id: Optional[str] = None
    display_name: Optional[str] = None


class CommunicationIncomingCallResponse(BaseModel):
    session_id: str
    call_id: Optional[str] = None
    display_name: Optional[str] = None
    state: str
    destination_type: str
    transport: str
    livekit_room_name: Optional[str] = None
    claim_id: Optional[str] = None
    caller_context: Optional[CommunicationCallerContext] = None
    notification_actions: list[CommunicationNotificationAction] = Field(default_factory=list)
    created_at: datetime


class CommunicationIncomingCallListResponse(BaseModel):
    items: list[CommunicationIncomingCallResponse] = Field(default_factory=list)


class ProviderWebhookRequest(BaseModel):
    provider: str = "telnyx"
    tenant_id: Optional[str] = None
    headers: dict[str, str] = Field(default_factory=dict)
    payload: dict[str, Any] = Field(default_factory=dict)


class ProviderWebhookResponse(BaseModel):
    event_id: str
    provider: str
    event_type: str
    signature_valid: bool
    action: dict[str, Any] = Field(default_factory=dict)
    session_id: Optional[str] = None
    call_id: Optional[str] = None
    caller_context: Optional[CommunicationCallerContext] = None
    notification_actions: list[CommunicationNotificationAction] = Field(default_factory=list)


class CommunicationSessionActionRequest(BaseModel):
    action_type: CommunicationNotificationActionType


class CommunicationSessionActionResponse(BaseModel):
    session_id: str
    call_id: Optional[str] = None
    action_type: CommunicationNotificationActionType
    state: str
    claim_id: Optional[str] = None
    open_claim: bool = False
    livekit_token: Optional[CommunicationLiveKitTokenResponse] = None
    provider_action: dict[str, Any] = Field(default_factory=dict)


class ScheduledCommunicationCreateRequest(BaseModel):
    title: str
    starts_at: datetime
    ends_at: datetime
    claim_id: Optional[str] = None
    internal_participants: list[str] = Field(default_factory=list)
    external_invites: list[dict[str, Any]] = Field(default_factory=list)
    reminders: list[dict[str, Any]] = Field(default_factory=list)


class ScheduledCommunicationResponse(BaseModel):
    id: str
    tenant_id: str
    title: str
    starts_at: datetime
    ends_at: datetime
    state: str
    livekit_room_name: Optional[str] = None
    claim_id: Optional[str] = None


class ExternalInviteCreateRequest(BaseModel):
    session_id: Optional[str] = None
    scheduled_communication_id: Optional[str] = None
    claim_id: Optional[str] = None
    guest_role: str
    valid_from: datetime
    valid_until: datetime
    permissions: dict[str, Any] = Field(default_factory=dict)


class ExternalInviteResponse(BaseModel):
    id: str
    url_path: str
    guest_role: str
    valid_from: datetime
    valid_until: datetime
    revoked_at: Optional[datetime] = None


class ExtensionAssignRequest(BaseModel):
    user_id: str
    extension_number: Optional[str] = None
    display_name: Optional[str] = None


class ExtensionDisableRequest(BaseModel):
    user_id: str


class ExtensionLookupResponse(BaseModel):
    user_id: str
    tenant_id: str
    extension_number: str
    display_name: str
    availability_status: AvailabilityStatus
    communication_status: CommunicationStatus
