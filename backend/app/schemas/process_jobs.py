"""
Schemas for the general process job queue.
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ProcessJobCreateRequest(BaseModel):
    job_type: str = Field(min_length=1, max_length=120)
    claim_id: Optional[str] = None
    priority: int = 0
    max_retries: int = Field(default=5, ge=0, le=20)
    available_at: Optional[datetime] = None
    idempotency_key: Optional[str] = Field(default=None, max_length=240)
    input_json: dict = Field(default_factory=dict)
    tags_json: Optional[dict] = None


class ProcessJobResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    created_by_user_id: Optional[str] = None
    job_type: str
    status: str
    priority: int
    retry_count: int
    max_retries: int
    available_at: datetime
    lease_owner: Optional[str] = None
    lease_expires_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    last_heartbeat_at: Optional[datetime] = None
    last_error: Optional[str] = None
    idempotency_key: Optional[str] = None
    input_json: dict
    result_json: Optional[dict] = None
    tags_json: Optional[dict] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProcessJobClaimResponse(BaseModel):
    items: list[ProcessJobResponse]
    total: int


class ProcessJobCompleteRequest(BaseModel):
    result_json: dict = Field(default_factory=dict)


class ProcessJobFailRequest(BaseModel):
    error: str
    retry: bool = True
    result_json: Optional[dict] = None


class ProcessJobHeartbeatRequest(BaseModel):
    lease_seconds: int = Field(default=300, ge=30, le=3600)
