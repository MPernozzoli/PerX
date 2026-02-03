from __future__ import annotations

from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request, status

from api import get_filesystem_service, get_registry, get_watcher_service, register_watcher
from models import GenericResponse, MonitoringChangesResponse, MonitoringEntry, MonitoringListResponse, RegisterMonitoringRequest
from services.auth_service import get_token
from services.file_watcher_service import FileWatcherService
from services.filesystem_service import FilesystemService
from services.monitoring_registry import MonitoringRegistry

router = APIRouter(prefix="/api/monitoring", tags=["monitoring"])


def _on_change_factory(registry: MonitoringRegistry):
    def _on_change(path):
        # Aggiorna last_change_at per il claim associato
        for entry in registry.list():
            try:
                if Path(path).resolve().is_relative_to(entry.root_path):
                    registry.touch_change(entry.user_id, entry.claim_id)
                    break
            except Exception:
                continue
    return _on_change


@router.post("/register", response_model=GenericResponse)
def register(
    payload: RegisterMonitoringRequest,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
    watcher: FileWatcherService = Depends(get_watcher_service),
):
    path = fs_service.resolve_claim_path(payload.user_id, payload.claim_id, payload.path_hint)
    entry = MonitoringEntry(
        user_id=payload.user_id,
        claim_id=payload.claim_id,
        root_path=path,
        added_at=datetime.utcnow(),
    )
    fs_service.ensure_claim_dir(path)
    registry.register(entry)
    register_watcher(entry, watcher, _on_change_factory(registry))
    return GenericResponse(success=True, message="Sinistro registrato", details={"path": str(path)})


@router.post("/unregister", response_model=GenericResponse)
def unregister(
    payload: RegisterMonitoringRequest,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    watcher: FileWatcherService = Depends(get_watcher_service),
):
    entry = registry.get(payload.user_id, payload.claim_id)
    if not entry:
        return GenericResponse(success=False, message="Sinistro non registrato")
    watcher.unwatch(entry.root_path)
    ok = registry.unregister(payload.user_id, payload.claim_id)
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Entry non trovata")
    return GenericResponse(success=True, message="Sinistro rimosso dal monitoring")


@router.get("/list", response_model=MonitoringListResponse)
def list_entries(
    user_id: str | None = None,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
):
    entries = list(registry.list())
    if user_id:
        entries = [e for e in entries if e.user_id == user_id]
    return MonitoringListResponse(total_entries=len(entries), entries=entries)


@router.get("/changes", response_model=MonitoringChangesResponse)
def changes(
    user_id: str | None = None,
    since: datetime | None = None,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
):
    entries = registry.list_changed_since(user_id, since)
    return MonitoringChangesResponse(total_entries=len(entries), entries=entries)


@router.get("/wait", response_model=MonitoringChangesResponse)
def wait_for_changes(
    user_id: str | None = None,
    since: datetime | None = None,
    timeout: float = 25.0,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
):
    # hard clamp per evitare connessioni "appese" troppo a lungo
    t = max(1.0, min(float(timeout), 55.0))
    entries = registry.wait_for_changes(user_id, since, t)
    return MonitoringChangesResponse(total_entries=len(entries), entries=entries)