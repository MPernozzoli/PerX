from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, List

from pydantic import BaseModel, Field


UserId = str
ClaimId = str


class MonitoringEntry(BaseModel):
    user_id: UserId
    claim_id: ClaimId
    root_path: Path
    added_at: datetime = Field(default_factory=datetime.utcnow)
    last_sync_at: Optional[datetime] = None
    last_change_at: Optional[datetime] = None

    class Config:
        arbitrary_types_allowed = True


class ClaimMetadataResponse(BaseModel):
    user_id: UserId
    claim_id: ClaimId
    total_files: int
    total_bytes: int
    directory_count: int
    relative_root: str
    # Estensione per sync differenziale
    files: Optional[List["ClaimFileEntry"]] = None
    directories: Optional[List[str]] = None


class ClaimFileEntry(BaseModel):
    relativePath: str
    size: int
    md5: str
    modifiedAt: Optional[datetime] = None


class RegisterMonitoringRequest(BaseModel):
    user_id: UserId
    claim_id: ClaimId
    path_hint: Optional[str] = None


class CreateDirectoriesRequest(BaseModel):
    user_id: UserId
    claim_id: ClaimId
    directories: list[str] = Field(default_factory=list)
    subpath: Optional[str] = None


class MonitoringListResponse(BaseModel):
    total_entries: int
    entries: List[MonitoringEntry]


class MonitoringChangesResponse(BaseModel):
    server_time: datetime = Field(default_factory=datetime.utcnow)
    total_entries: int
    entries: List[MonitoringEntry]


class GenericResponse(BaseModel):
    success: bool
    message: str
    details: Optional[Dict[str, str]] = None


ClaimMetadataResponse.model_rebuild()