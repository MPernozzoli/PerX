"""
Schemas for folders, documents and diary
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ClaimFolderCreate(BaseModel):
    name: str
    parent_id: Optional[str] = None
    folder_type: str = "generic"
    path: Optional[str] = None
    source: str = "hub"
    external_ref: Optional[str] = None
    metadata_json: Optional[dict] = None


class ClaimFolderResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    parent_id: Optional[str] = None
    name: str
    folder_type: str
    path: str
    source: str
    external_ref: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class ClaimFolderListResponse(BaseModel):
    items: list[ClaimFolderResponse]
    total: int


class DocumentCreate(BaseModel):
    claim_id: Optional[str] = None
    folder_id: Optional[str] = None
    attachment_id: Optional[str] = None
    source_type: str = "hub"
    source_id: Optional[str] = None
    file_name: str
    original_file_name: Optional[str] = None
    mime_type: Optional[str] = None
    extension: Optional[str] = None
    size_bytes: int = 0
    storage_provider: str = "hub"
    storage_bucket: Optional[str] = None
    storage_path: str
    logical_path: Optional[str] = None
    checksum_sha256: Optional[str] = None
    checksum_md5: Optional[str] = None
    version_no: int = 1
    status: str = "active"
    category: Optional[str] = None
    tags_json: list[str] = Field(default_factory=list)
    metadata_json: Optional[dict] = None


class DocumentUpdate(BaseModel):
    folder_id: Optional[str] = None
    status: Optional[str] = None
    category: Optional[str] = None
    logical_path: Optional[str] = None
    tags_json: Optional[list[str]] = None
    metadata_json: Optional[dict] = None


class DocumentResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: Optional[str] = None
    folder_id: Optional[str] = None
    attachment_id: Optional[str] = None
    source_type: str
    source_id: Optional[str] = None
    file_name: str
    original_file_name: Optional[str] = None
    mime_type: Optional[str] = None
    extension: Optional[str] = None
    size_bytes: int
    storage_provider: str
    storage_bucket: Optional[str] = None
    storage_path: str
    logical_path: Optional[str] = None
    checksum_sha256: Optional[str] = None
    checksum_md5: Optional[str] = None
    version_no: int
    status: str
    category: Optional[str] = None
    tags_json: Optional[list[str]] = None
    uploaded_at: datetime
    uploaded_by_user_id: Optional[str] = None
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class DocumentListResponse(BaseModel):
    items: list[DocumentResponse]
    total: int


class ClaimDiaryEntryCreate(BaseModel):
    entry_type: str = "note"
    title: Optional[str] = None
    body_text: Optional[str] = None
    visibility: str = "internal"
    happened_at: Optional[datetime] = None
    metadata_json: Optional[dict] = None


class ClaimDiaryEntryResponse(BaseModel):
    id: str
    tenant_id: str
    claim_id: str
    entry_type: str
    title: Optional[str] = None
    body_text: Optional[str] = None
    visibility: str
    happened_at: datetime
    created_at: datetime
    created_by_user_id: Optional[str] = None
    metadata_json: Optional[dict] = None

    class Config:
        from_attributes = True


class ClaimDiaryEntryListResponse(BaseModel):
    items: list[ClaimDiaryEntryResponse]
    total: int
