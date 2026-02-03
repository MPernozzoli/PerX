from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from api import get_filesystem_service, get_registry
from models import CreateDirectoriesRequest, GenericResponse
from services.auth_service import get_token
from services.filesystem_service import FilesystemService
from services.monitoring_registry import MonitoringRegistry

router = APIRouter(prefix="/api/claims", tags=["upload"])


@router.post("/{claim_id}/upload", response_model=GenericResponse)
async def upload(
    claim_id: str,
    user_id: str,
    subpath: Optional[str] = None,
    files: List[UploadFile] = File(...),
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
):
    entry = registry.get(user_id, claim_id)
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sinistro non monitorato")
    saved = await fs_service.save_uploads(entry, files, subpath=subpath)
    return GenericResponse(success=True, message="Upload completato", details=saved)


@router.post("/{claim_id}/mkdir", response_model=GenericResponse)
def mkdir(
    claim_id: str,
    payload: CreateDirectoriesRequest,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
):
    user_id = payload.user_id
    entry = registry.get(user_id, claim_id)
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sinistro non monitorato")

    created = fs_service.ensure_directories(entry, payload.directories, subpath=payload.subpath)
    return GenericResponse(success=True, message="Directory create", details=created)

