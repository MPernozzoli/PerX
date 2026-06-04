"""
Pydantic schemas for the videoperizia (video-inspection) live-call API.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, ConfigDict


class VideoperiziaSessionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    claim_id: str
    livekit_room_name: str
    state: str
    lobby_joined_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    perito_user_id: Optional[str] = None
    insured_disconnected_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class VideoperiziaSessionCreateResponse(BaseModel):
    session: VideoperiziaSessionResponse


class VideoperiziaLobbyJoinRequest(BaseModel):
    """Insured signals from the portal that they're in the lobby and ready."""
    client_meta: Optional[dict[str, Any]] = None


class VideoperiziaSessionEndRequest(BaseModel):
    reason: Optional[str] = None


class VideoperiziaEndResponse(BaseModel):
    """
    Returned by POST /session/{sid}/end.

    When `needs_outcome_confirmation` is True the expert app must present the
    outcome dialog (< 3 frames captured). The claim has NOT been transitioned
    yet — the client must call POST /session/{sid}/outcome to complete the flow.

    When False the claim has already been moved to DA_GESTIRE_VIDEO automatically.
    """
    session: VideoperiziaSessionResponse
    needs_outcome_confirmation: bool
    frame_count: int


# Possible decisions the expert makes after a low-evidence inspection:
#   confirmed          → claim → DA_GESTIRE_VIDEO (standard handoff)
#   reschedule_video   → claim stays VIDEOPERIZIA, resets to da_fissare so the
#                        insured receives a new scheduling notification
#   escalate_sopralluogo → claim → SOPRALLUOGO da_fissare (physical CAT inspection)
VideoperiziaOutcomeChoice = Literal["confirmed", "reschedule_video", "escalate_sopralluogo"]


class VideoperiziaOutcomeRequest(BaseModel):
    outcome: VideoperiziaOutcomeChoice


class VideoperiziaTokenResponse(BaseModel):
    token: str
    livekit_url: str
    room_name: str
    identity: str
    expires_at: datetime
    can_publish: bool
    can_subscribe: bool
    session: VideoperiziaSessionResponse


class VideoperiziaMediaResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    session_id: str
    claim_id: str
    kind: str
    storage_path: str
    mime_type: Optional[str] = None
    captured_at: datetime
    captured_by_user_id: Optional[str] = None
    processing_status: str
    hub_result_json: Optional[dict[str, Any]] = None
    signed_url: Optional[str] = None


class VideoperiziaMediaListResponse(BaseModel):
    items: list[VideoperiziaMediaResponse]


class VideoperiziaLocationPingCreate(BaseModel):
    """Portal-side ping payload. session_id is resolved from the active session."""
    latitude: float
    longitude: float
    accuracy_m: Optional[float] = None
    altitude_m: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_deg: Optional[float] = None
    recorded_at: Optional[datetime] = None


class VideoperiziaLocationPingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    session_id: str
    recorded_at: datetime
    latitude: float
    longitude: float
    accuracy_m: Optional[float] = None
    altitude_m: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_deg: Optional[float] = None
    source: str


class VideoperiziaLocationPingListResponse(BaseModel):
    items: list[VideoperiziaLocationPingResponse]
