"""
Schemas for emails and attachments
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class EmailCreate(BaseModel):
    message_id: str
    thread_id: Optional[str] = None
    from_address: str
    to_addresses: list[str] = Field(default_factory=list)
    cc_addresses: list[str] = Field(default_factory=list)
    subject: Optional[str] = None
    body_text: Optional[str] = None
    body_html: Optional[str] = None
    received_at: datetime
    status: str = "ingested"
    raw_headers: Optional[str] = None
    mailbox_id: Optional[str] = None
    provider_id: Optional[str] = None


class EmailClaimLinkRequest(BaseModel):
    claim_id: str
    link_type: str = "primary"
    created_by: str = "user"


class EmailResponse(BaseModel):
    id: str
    tenant_id: str
    message_id: str
    thread_id: Optional[str] = None
    from_address: str
    to_addresses: Optional[str] = None
    cc_addresses: Optional[str] = None
    subject: Optional[str] = None
    body_text: Optional[str] = None
    body_html: Optional[str] = None
    received_at: datetime
    ingested_at: datetime
    status: str
    raw_headers: Optional[str] = None
    mailbox_id: Optional[str] = None
    provider_id: Optional[str] = None

    class Config:
        from_attributes = True


class EmailListResponse(BaseModel):
    items: list[EmailResponse]
    total: int


class EmailProcessingJobResponse(BaseModel):
    id: str
    tenant_id: str
    inbound_event_id: str
    status: str
    priority: int
    retry_count: int
    input_json: dict
    lease_expires_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class EmailProcessingJobClaimResponse(BaseModel):
    items: list[EmailProcessingJobResponse]
    total: int


class EmailProcessingJobCompleteRequest(BaseModel):
    email_id: Optional[str] = None
    result_json: dict = Field(default_factory=dict)


class EmailProcessingJobFailRequest(BaseModel):
    error: str
    retry: bool = True
    result_json: Optional[dict] = None


class AttachmentCreate(BaseModel):
    email_id: Optional[str] = None
    claim_id: Optional[str] = None
    file_name: str
    mime_type: Optional[str] = None
    size_bytes: int
    storage_bucket: str
    storage_path: str
    checksum: Optional[str] = None


class AttachmentResponse(BaseModel):
    id: str
    tenant_id: str
    email_id: Optional[str] = None
    claim_id: Optional[str] = None
    file_name: str
    mime_type: Optional[str] = None
    size_bytes: int
    storage_bucket: str
    storage_path: str
    checksum: Optional[str] = None
    uploaded_at: datetime
    uploaded_by_user_id: Optional[str] = None

    class Config:
        from_attributes = True


class AttachmentListResponse(BaseModel):
    items: list[AttachmentResponse]
    total: int

