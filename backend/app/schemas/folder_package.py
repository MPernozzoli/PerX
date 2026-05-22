"""
Pydantic schemas for sinistro folder package requests
"""
from __future__ import annotations
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel


class FolderRequestCreate(BaseModel):
    claim_id: Optional[str] = None
    riferimento: str


class FolderRequestStatusUpdate(BaseModel):
    status: str  # pending | processing | ready | error
    error_message: Optional[str] = None


class FolderRequestReadyUpdate(BaseModel):
    download_url: str


class FolderRequestResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    riferimento: str
    requested_by_user_id: Optional[str] = None
    status: str
    download_url: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    completed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class FolderRequestListResponse(BaseModel):
    items: List[FolderRequestResponse]
    total: int
