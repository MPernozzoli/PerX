"""
Schemas for internal chat, AI chat and planning
"""
from datetime import date, datetime, time
from typing import Optional

from pydantic import BaseModel, Field


class InternalChatThreadCreate(BaseModel):
    claim_id: Optional[str] = None
    title: str
    thread_type: str = "claim"
    member_user_ids: list[str] = Field(default_factory=list)
    metadata_json: Optional[dict] = None


class InternalChatMessageCreate(BaseModel):
    body_text: Optional[str] = None
    message_type: str = "text"
    attachment_document_id: Optional[str] = None
    metadata_json: Optional[dict] = None


class InternalChatThreadResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    title: str
    thread_type: str
    created_at: datetime
    created_by_user_id: Optional[str] = None
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class InternalChatMessageResponse(BaseModel):
    id: str
    tenant_id: str
    thread_id: str
    claim_id: Optional[str] = None
    sender_user_id: Optional[str] = None
    body_text: Optional[str] = None
    message_type: str
    attachment_document_id: Optional[str] = None
    created_at: datetime
    edited_at: Optional[datetime] = None
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class InternalChatThreadListResponse(BaseModel):
    items: list[InternalChatThreadResponse]
    total: int


class InternalChatMessageListResponse(BaseModel):
    items: list[InternalChatMessageResponse]
    total: int


class AIChatSessionCreate(BaseModel):
    claim_id: Optional[str] = None
    title: str
    model: Optional[str] = None
    context_json: Optional[dict] = None


class AIChatMessageCreate(BaseModel):
    role: str
    body_text: Optional[str] = None
    payload_json: Optional[dict] = None


class AIChatSessionResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    user_id: str
    title: str
    model: Optional[str] = None
    status: str
    context_json: Optional[dict] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class AIChatMessageResponse(BaseModel):
    id: str
    tenant_id: str
    session_id: str
    role: str
    body_text: Optional[str] = None
    payload_json: Optional[dict] = None
    created_at: datetime

    class Config:
        from_attributes = True


class AIChatSessionListResponse(BaseModel):
    items: list[AIChatSessionResponse]
    total: int


class AIChatMessageListResponse(BaseModel):
    items: list[AIChatMessageResponse]
    total: int


class UserWorkScheduleCreate(BaseModel):
    user_id: Optional[str] = None
    weekday: int
    start_time: time
    end_time: time
    location: Optional[str] = None
    slot_type: str = "work"
    effective_from: Optional[date] = None
    effective_to: Optional[date] = None
    metadata_json: Optional[dict] = None


class UserWorkScheduleResponse(BaseModel):
    id: str
    tenant_id: str
    user_id: str
    weekday: int
    start_time: time
    end_time: time
    location: Optional[str] = None
    slot_type: str
    effective_from: Optional[date] = None
    effective_to: Optional[date] = None
    created_at: datetime
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class UserWorkScheduleUpdate(BaseModel):
    weekday: Optional[int] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    location: Optional[str] = None
    slot_type: Optional[str] = None
    effective_from: Optional[date] = None
    effective_to: Optional[date] = None
    metadata_json: Optional[dict] = None


class UserWorkScheduleListResponse(BaseModel):
    items: list[UserWorkScheduleResponse]
    total: int


class CalendarEventCreate(BaseModel):
    claim_id: Optional[str] = None
    task_id: Optional[str] = None
    owner_user_id: Optional[str] = None
    title: str
    description: Optional[str] = None
    event_type: str = "appointment"
    starts_at: datetime
    ends_at: datetime
    all_day: bool = False
    location: Optional[str] = None
    status: str = "confirmed"
    visibility: str = "tenant"
    source: str = "manual"
    metadata_json: Optional[dict] = None


class CalendarEventUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    event_type: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    all_day: Optional[bool] = None
    location: Optional[str] = None
    status: Optional[str] = None
    visibility: Optional[str] = None
    metadata_json: Optional[dict] = None


class CalendarEventResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    task_id: Optional[str] = None
    owner_user_id: str
    title: str
    description: Optional[str] = None
    event_type: str
    starts_at: datetime
    ends_at: datetime
    all_day: bool
    location: Optional[str] = None
    status: str
    visibility: str
    source: str
    metadata_json: Optional[dict] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class CalendarEventListResponse(BaseModel):
    items: list[CalendarEventResponse]
    total: int


class DashboardWidgetUpsert(BaseModel):
    widget_key: str
    position: int = 0
    enabled: bool = True
    settings_json: Optional[dict] = None


class DashboardWidgetResponse(BaseModel):
    id: str
    tenant_id: str
    user_id: str
    widget_key: str
    position: int
    enabled: bool
    settings_json: Optional[dict] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class DashboardWidgetListResponse(BaseModel):
    items: list[DashboardWidgetResponse]
    total: int
